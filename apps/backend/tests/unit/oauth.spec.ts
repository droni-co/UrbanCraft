import { test } from '@japa/runner'
import { nicknameBase } from '#services/oauth_login_service'

test.group('nicknameBase', () => {
  test('quita tildes, espacios y símbolos', ({ assert }) => {
    assert.equal(nicknameBase('José María'), 'JoseMaria')
    assert.equal(nicknameBase('Ñandú-Pérez'), 'NanduPerez')
  })

  test('usa "Jugador" si queda muy corto y recorta a 16', ({ assert }) => {
    assert.equal(nicknameBase('李'), 'Jugador')
    assert.equal(nicknameBase('Al'), 'Jugador')
    assert.lengthOf(nicknameBase('Maximilianoalejandro'), 16)
  })
})

test.group('devSlug', () => {
  test('normaliza el nombre para el email de prueba', async ({ assert }) => {
    const { devSlug } = await import('#services/oauth_login_service')
    assert.equal(devSlug('José_Mª'), 'jose_ma')
    assert.match(devSlug('李'), /^u[0-9a-f]{10}$/)
  })
})

test.group('levelFromXp', () => {
  test('curva base·N^1.5', async ({ assert }) => {
    const { levelFromXp } = await import('#services/player_stats_service')
    const curve = { base: 100, exponent: 1.5, maxLevel: 100 }
    assert.deepInclude(levelFromXp(0, curve), { level: 1, current: 0, needed: 100 })
    assert.deepInclude(levelFromXp(99, curve), { level: 1, current: 99 })
    assert.deepInclude(levelFromXp(100, curve), { level: 2, current: 0, needed: 283 })
    assert.deepInclude(levelFromXp(383, curve), { level: 3, current: 0, needed: 520 })
    assert.deepInclude(levelFromXp(10 ** 12, { ...curve, maxLevel: 5 }), { level: 5, progress: 1 })
  })
})
