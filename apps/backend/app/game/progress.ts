import { ACHIEVEMENTS_BY_COUNTER } from '#game/catalog/achievements'
import { ITEMS_BY_KEY } from '#game/catalog/items'
import { NPCS, STORY, type GoalDefinition, type StepDefinition } from '#game/catalog/story'
import type { GameStore } from '#game/store'
import type { Ctx, PlayerState, Trx } from '#game/types'

export interface GoalView {
  text: string
  type: GoalDefinition['type']
  progress: number
  count: number
  done: boolean
  /** Metas "talk": con quién y en qué tipo de lugares. */
  npc?: string
  cats?: string[]
}

export interface StoryView {
  finished: boolean
  index: number
  total: number
  chapter: { key: string; title: string; summary: string; npc: string } | null
  hint: string
  goals: GoalView[]
  /** Diálogo que el cliente debe mostrar al entrar (entrada del paso o cierre pendiente). */
  dialog: { npc: string; lines: string[] } | null
}

interface Snapshot {
  counters: Record<string, number>
  inventory: Record<string, number>
  money: number
  level: number
}

/**
 * Progreso del jugador: recompensas, logros e historia. Todo se revisa al
 * final de cada acción (finish), a partir de los contadores que cambiaron.
 */
export class Progress {
  constructor(private store: GameStore) {}

  /** Da dinero, experiencia u objetos, y lo anota como evento para el cliente. */
  async reward(
    ctx: Ctx,
    reward: { money?: number; xp?: number; items?: Record<string, number> },
    reason?: string,
    forceItems = false
  ) {
    const money = Math.round(reward.money ?? 0)
    const xp = Math.round(reward.xp ?? 0)
    if (money > 0) {
      const total = await this.store.addStat(ctx.trx, ctx.userId, 'money', money)
      await this.store.count(ctx, 'money_earned', money)
      await this.store.setCounter(ctx, 'money_max', total, true)
    }
    if (xp > 0) {
      await this.store.addStat(ctx.trx, ctx.userId, 'xp', xp)
      await this.store.setCounter(ctx, 'level', await this.store.level(ctx.trx, ctx.userId), true)
    }
    if (reward.items && Object.keys(reward.items).length > 0) {
      await this.store.addItems(ctx.trx, ctx.userId, reward.items, forceItems)
    }
    if (money > 0 || xp > 0 || reward.items) {
      ctx.events.push({
        type: 'reward',
        ...(reason ? { reason } : {}),
        ...(money > 0 ? { money } : {}),
        ...(xp > 0 ? { xp } : {}),
        ...(reward.items ? { items: reward.items } : {}),
      })
    }
  }

  /** Revisa logros e historia con lo que cambió en la acción. */
  async finish(ctx: Ctx) {
    for (let round = 0; round < 6; round++) {
      const unlocked = await this.#achievements(ctx)
      const advanced = await this.#story(ctx)
      if (!unlocked && !advanced) break
    }
  }

  // --- Logros ------------------------------------------------------------------

  async #achievements(ctx: Ctx) {
    const keys = [...ctx.touched].filter((key) => ACHIEVEMENTS_BY_COUNTER.has(key))
    ctx.touched.clear()
    if (keys.length === 0) return false
    const counters = await this.store.counters(ctx.trx, ctx.userId)
    const rows = await ctx.trx
      .from('player_achievements')
      .where('user_id', ctx.userId)
      .select('key')
    const have = new Set(rows.map((r) => r.key))
    let unlocked = false
    for (const key of keys) {
      for (const achievement of ACHIEVEMENTS_BY_COUNTER.get(key)!) {
        if (have.has(achievement.key) || (counters[key] ?? 0) < achievement.count) continue
        await ctx.trx
          .insertQuery()
          .table('player_achievements')
          .insert({ user_id: ctx.userId, key: achievement.key, unlocked_at: ctx.now })
        have.add(achievement.key)
        unlocked = true
        ctx.events.push({
          type: 'achievement',
          key: achievement.key,
          name: achievement.name,
          desc: achievement.desc,
          tier: achievement.tier,
          emblem: achievement.emblem,
        })
        await this.reward(ctx, achievement.reward, `Logro: ${achievement.name}`)
        await this.store.count(ctx, 'achievements')
      }
    }
    return unlocked
  }

  // --- Historia ----------------------------------------------------------------

  async #snapshot(trx: Trx, userId: number): Promise<Snapshot> {
    return {
      counters: await this.store.counters(trx, userId),
      inventory: await this.store.inventory(trx, userId),
      money: await this.store.stat(trx, userId, 'money'),
      level: await this.store.level(trx, userId),
    }
  }

  #goal(goal: GoalDefinition, index: number, state: PlayerState, snap: Snapshot): GoalView {
    let progress = 0
    let count = 1
    switch (goal.type) {
      case 'counter':
        progress = (snap.counters[goal.key] ?? 0) - (state.story.base[goal.key] ?? 0)
        count = goal.count
        break
      case 'total':
        progress = snap.counters[goal.key] ?? 0
        count = goal.count
        break
      case 'stat':
        progress = goal.key === 'money' ? snap.money : snap.level
        count = goal.count
        break
      case 'have':
        progress = snap.inventory[goal.item] ?? 0
        count = goal.count
        break
      case 'talk':
        progress = state.story.talked.includes(index) ? 1 : 0
        break
    }
    progress = Math.max(0, Math.min(Math.floor(progress), count))
    return {
      text: goal.text,
      type: goal.type,
      progress,
      count,
      done: progress >= count,
      ...(goal.type === 'talk' ? { npc: goal.npc, cats: goal.cats } : {}),
    }
  }

  /** Empieza un paso: guarda de dónde parten sus contadores y entrega lo que da. */
  async #begin(ctx: Ctx, step: StepDefinition, snap: Snapshot, announce: boolean) {
    const story = ctx.state.story
    story.base = {}
    story.talked = []
    for (const goal of step.goals) {
      if (goal.type === 'counter') story.base[goal.key] = snap.counters[goal.key] ?? 0
    }
    if (step.give) {
      await this.reward(ctx, { items: step.give }, undefined, true)
    }
    story.introSeen = false
    if (announce && step.intro) {
      ctx.events.push({ type: 'dialog', npc: step.intro.npc, lines: step.intro.lines })
      story.introSeen = true
    }
  }

  /** Avanza la historia si el paso actual está cumplido. true si avanzó. */
  async #story(ctx: Ctx) {
    const story = ctx.state.story
    const chapter = STORY[story.chapter]
    if (!chapter) return false
    const snap = await this.#snapshot(ctx.trx, ctx.userId)
    const step = chapter.steps[story.step]
    const goals = step.goals.map((goal, index) => this.#goal(goal, index, ctx.state, snap))
    if (!goals.every((goal) => goal.done)) return false

    if (story.step + 1 < chapter.steps.length) {
      story.step++
      ctx.events.push({
        type: 'story',
        kind: 'step',
        title: chapter.title,
        text: '¡Objetivo cumplido!',
      })
    } else {
      ctx.events.push({
        type: 'story',
        kind: 'chapter',
        title: chapter.title,
        text: 'Capítulo completado',
      })
      ctx.events.push({ type: 'dialog', npc: chapter.outro.npc, lines: chapter.outro.lines })
      await this.reward(ctx, chapter.reward, `Capítulo: ${chapter.title}`, true)
      await this.store.count(ctx, 'chapters')
      story.chapter++
      story.step = 0
    }
    const next = STORY[story.chapter]
    if (next) {
      await this.#begin(
        ctx,
        next.steps[story.step],
        await this.#snapshot(ctx.trx, ctx.userId),
        true
      )
    } else {
      story.base = {}
      story.talked = []
    }
    return true
  }

  /** Jugador nuevo: prepara el primer paso (su diálogo lo muestra el cliente al entrar). */
  async start(ctx: Ctx) {
    const first = STORY[0].steps[0]
    await this.#begin(ctx, first, await this.#snapshot(ctx.trx, ctx.userId), false)
  }

  /** Meta "talk" del paso actual que se puede cumplir en un lugar de esta categoría. */
  talkGoal(state: PlayerState, category: string | null) {
    const step = STORY[state.story.chapter]?.steps[state.story.step]
    if (!step) return null
    for (const [index, goal] of step.goals.entries()) {
      if (goal.type !== 'talk' || state.story.talked.includes(index)) continue
      if (category === null || goal.cats.includes(category)) return { index, goal }
    }
    return null
  }

  async view(trx: Trx, userId: number, state: PlayerState): Promise<StoryView> {
    const story = state.story
    const chapter = STORY[story.chapter]
    if (!chapter) {
      return {
        finished: true,
        index: STORY.length,
        total: STORY.length,
        chapter: null,
        hint: 'Terminaste la historia. La ciudad es tuya: cuídala.',
        goals: [],
        dialog: null,
      }
    }
    const snap = await this.#snapshot(trx, userId)
    const step = chapter.steps[story.step]
    return {
      finished: false,
      index: story.chapter,
      total: STORY.length,
      chapter: {
        key: chapter.key,
        title: chapter.title,
        summary: chapter.summary,
        npc: chapter.npc,
      },
      hint: step.hint ?? '',
      goals: step.goals.map((goal, index) => this.#goal(goal, index, state, snap)),
      dialog: !story.introSeen && step.intro ? step.intro : null,
    }
  }
}

/** Nombre para mostrar de un objeto (para mensajes). */
export function itemName(key: string) {
  return ITEMS_BY_KEY.get(key)?.name ?? key
}

export function npcName(key: string) {
  return NPCS[key]?.name ?? key
}
