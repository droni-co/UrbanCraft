/* eslint-disable prettier/prettier */
import type { routes } from './index.ts'

export interface ApiDefinition {
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
  map: {
    map: {
      config: typeof routes['map.map.config']
      chunk: typeof routes['map.map.chunk']
    }
  }
  geo: {
    geo: {
      place: typeof routes['geo.geo.place']
      ip: typeof routes['geo.geo.ip']
    }
  }
}
