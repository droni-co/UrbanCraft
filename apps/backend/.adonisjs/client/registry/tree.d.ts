/* eslint-disable prettier/prettier */
import type { routes } from './index.ts'

export interface ApiDefinition {
  play: typeof routes['play'] & {
    file: typeof routes['play.file']
  }
  googleBrowser: {
    redirect: typeof routes['google_browser.redirect']
    callback: typeof routes['google_browser.callback']
  }
  auth: {
    newAccount: {
      store: typeof routes['auth.new_account.store']
    }
    accessTokens: {
      store: typeof routes['auth.access_tokens.store']
    }
    google: {
      start: typeof routes['auth.google.start']
      poll: typeof routes['auth.google.poll']
    }
    methods: typeof routes['auth.methods']
    dev: {
      login: typeof routes['auth.dev.login']
    }
  }
  profile: {
    profile: {
      show: typeof routes['profile.profile.show']
      update: typeof routes['profile.profile.update']
    }
    accessTokens: {
      destroy: typeof routes['profile.access_tokens.destroy']
    }
  }
  player: {
    stats: typeof routes['player.stats'] & {
      dev: typeof routes['player.stats.dev']
    }
    heartbeat: typeof routes['player.heartbeat']
  }
  friends: {
    index: typeof routes['friends.index']
    search: typeof routes['friends.search']
    requests: {
      store: typeof routes['friends.requests.store']
      accept: typeof routes['friends.requests.accept']
      reject: typeof routes['friends.requests.reject']
    }
    location: typeof routes['friends.location']
    destroy: typeof routes['friends.destroy']
  }
  game: {
    catalog: typeof routes['game.catalog']
    state: typeof routes['game.state']
    story: {
      seen: typeof routes['game.story.seen']
      talk: typeof routes['game.story.talk']
    }
    places: {
      visit: typeof routes['game.places.visit']
      buy: typeof routes['game.places.buy']
      sell: typeof routes['game.places.sell']
      work: typeof routes['game.places.work']
      service: typeof routes['game.places.service']
    }
    gather: typeof routes['game.gather']
    items: {
      use: typeof routes['game.items.use']
    }
    craft: typeof routes['game.craft']
    jobs: typeof routes['game.jobs'] & {
      refresh: typeof routes['game.jobs.refresh']
      accept: typeof routes['game.jobs.accept']
      abandon: typeof routes['game.jobs.abandon']
      step: typeof routes['game.jobs.step']
    }
    territory: typeof routes['game.territory'] & {
      collect: typeof routes['game.territory.collect']
    }
    objects: typeof routes['game.objects'] & {
      place: typeof routes['game.objects.place']
      act: typeof routes['game.objects.act']
    }
    dev: typeof routes['game.dev']
  }
  map: {
    map: {
      config: typeof routes['map.map.config']
      chunk: typeof routes['map.map.chunk']
    }
  }
  time: typeof routes['time']
  geo: {
    geo: {
      place: typeof routes['geo.geo.place']
      ip: typeof routes['geo.geo.ip']
    }
  }
}
