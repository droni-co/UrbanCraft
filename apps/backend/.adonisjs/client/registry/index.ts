/* eslint-disable prettier/prettier */
import type { AdonisEndpoint } from '@tuyau/core/types'
import type { Registry } from './schema.d.ts'
import type { ApiDefinition } from './tree.d.ts'

export type { Route, Path } from './schema.d.ts'

const placeholder: any = {}

const routes = {
  'play': {
    methods: ["GET","HEAD"],
    pattern: '/play',
    tokens: [[0,"play"]],
    types: placeholder as Registry['play']['types'],
  },
  'play.file': {
    methods: ["GET","HEAD"],
    pattern: '/play/*',
    tokens: [[0,"play"],[2,"*"]],
    types: placeholder as Registry['play.file']['types'],
  },
  'google_browser.redirect': {
    methods: ["GET","HEAD"],
    pattern: '/auth/google/redirect',
    tokens: [[0,"auth"],[0,"google"],[0,"redirect"]],
    types: placeholder as Registry['google_browser.redirect']['types'],
  },
  'google_browser.callback': {
    methods: ["GET","HEAD"],
    pattern: '/auth/google/callback',
    tokens: [[0,"auth"],[0,"google"],[0,"callback"]],
    types: placeholder as Registry['google_browser.callback']['types'],
  },
  'auth.new_account.store': {
    methods: ["POST"],
    pattern: '/api/v1/auth/signup',
    tokens: [[0,"api"],[0,"v1"],[0,"auth"],[0,"signup"]],
    types: placeholder as Registry['auth.new_account.store']['types'],
  },
  'auth.access_tokens.store': {
    methods: ["POST"],
    pattern: '/api/v1/auth/login',
    tokens: [[0,"api"],[0,"v1"],[0,"auth"],[0,"login"]],
    types: placeholder as Registry['auth.access_tokens.store']['types'],
  },
  'auth.google.start': {
    methods: ["POST"],
    pattern: '/api/v1/auth/google/start',
    tokens: [[0,"api"],[0,"v1"],[0,"auth"],[0,"google"],[0,"start"]],
    types: placeholder as Registry['auth.google.start']['types'],
  },
  'auth.google.poll': {
    methods: ["POST"],
    pattern: '/api/v1/auth/google/poll',
    tokens: [[0,"api"],[0,"v1"],[0,"auth"],[0,"google"],[0,"poll"]],
    types: placeholder as Registry['auth.google.poll']['types'],
  },
  'auth.methods': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/auth/methods',
    tokens: [[0,"api"],[0,"v1"],[0,"auth"],[0,"methods"]],
    types: placeholder as Registry['auth.methods']['types'],
  },
  'auth.dev.login': {
    methods: ["POST"],
    pattern: '/api/v1/auth/dev/login',
    tokens: [[0,"api"],[0,"v1"],[0,"auth"],[0,"dev"],[0,"login"]],
    types: placeholder as Registry['auth.dev.login']['types'],
  },
  'profile.profile.show': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/account/profile',
    tokens: [[0,"api"],[0,"v1"],[0,"account"],[0,"profile"]],
    types: placeholder as Registry['profile.profile.show']['types'],
  },
  'profile.profile.update': {
    methods: ["PATCH"],
    pattern: '/api/v1/account/profile',
    tokens: [[0,"api"],[0,"v1"],[0,"account"],[0,"profile"]],
    types: placeholder as Registry['profile.profile.update']['types'],
  },
  'profile.access_tokens.destroy': {
    methods: ["POST"],
    pattern: '/api/v1/account/logout',
    tokens: [[0,"api"],[0,"v1"],[0,"account"],[0,"logout"]],
    types: placeholder as Registry['profile.access_tokens.destroy']['types'],
  },
  'player.stats': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/player/stats',
    tokens: [[0,"api"],[0,"v1"],[0,"player"],[0,"stats"]],
    types: placeholder as Registry['player.stats']['types'],
  },
  'player.heartbeat': {
    methods: ["POST"],
    pattern: '/api/v1/player/heartbeat',
    tokens: [[0,"api"],[0,"v1"],[0,"player"],[0,"heartbeat"]],
    types: placeholder as Registry['player.heartbeat']['types'],
  },
  'player.stats.dev': {
    methods: ["POST"],
    pattern: '/api/v1/player/stats/dev',
    tokens: [[0,"api"],[0,"v1"],[0,"player"],[0,"stats"],[0,"dev"]],
    types: placeholder as Registry['player.stats.dev']['types'],
  },
  'friends.index': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/friends',
    tokens: [[0,"api"],[0,"v1"],[0,"friends"]],
    types: placeholder as Registry['friends.index']['types'],
  },
  'friends.search': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/friends/search',
    tokens: [[0,"api"],[0,"v1"],[0,"friends"],[0,"search"]],
    types: placeholder as Registry['friends.search']['types'],
  },
  'friends.requests.store': {
    methods: ["POST"],
    pattern: '/api/v1/friends/requests',
    tokens: [[0,"api"],[0,"v1"],[0,"friends"],[0,"requests"]],
    types: placeholder as Registry['friends.requests.store']['types'],
  },
  'friends.requests.accept': {
    methods: ["POST"],
    pattern: '/api/v1/friends/requests/:id/accept',
    tokens: [[0,"api"],[0,"v1"],[0,"friends"],[0,"requests"],[1,"id"],[0,"accept"]],
    types: placeholder as Registry['friends.requests.accept']['types'],
  },
  'friends.requests.reject': {
    methods: ["DELETE"],
    pattern: '/api/v1/friends/requests/:id',
    tokens: [[0,"api"],[0,"v1"],[0,"friends"],[0,"requests"],[1,"id"]],
    types: placeholder as Registry['friends.requests.reject']['types'],
  },
  'friends.location': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/friends/:userId/location',
    tokens: [[0,"api"],[0,"v1"],[0,"friends"],[1,"userId"],[0,"location"]],
    types: placeholder as Registry['friends.location']['types'],
  },
  'friends.destroy': {
    methods: ["DELETE"],
    pattern: '/api/v1/friends/:userId',
    tokens: [[0,"api"],[0,"v1"],[0,"friends"],[1,"userId"]],
    types: placeholder as Registry['friends.destroy']['types'],
  },
  'players.show': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/players/:id',
    tokens: [[0,"api"],[0,"v1"],[0,"players"],[1,"id"]],
    types: placeholder as Registry['players.show']['types'],
  },
  'game.catalog': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/game/catalog',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"catalog"]],
    types: placeholder as Registry['game.catalog']['types'],
  },
  'game.state': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/game/state',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"state"]],
    types: placeholder as Registry['game.state']['types'],
  },
  'game.story.seen': {
    methods: ["POST"],
    pattern: '/api/v1/game/story/seen',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"story"],[0,"seen"]],
    types: placeholder as Registry['game.story.seen']['types'],
  },
  'game.story.talk': {
    methods: ["POST"],
    pattern: '/api/v1/game/story/talk',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"story"],[0,"talk"]],
    types: placeholder as Registry['game.story.talk']['types'],
  },
  'game.places.visit': {
    methods: ["POST"],
    pattern: '/api/v1/game/places/visit',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"places"],[0,"visit"]],
    types: placeholder as Registry['game.places.visit']['types'],
  },
  'game.places.buy': {
    methods: ["POST"],
    pattern: '/api/v1/game/places/buy',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"places"],[0,"buy"]],
    types: placeholder as Registry['game.places.buy']['types'],
  },
  'game.places.sell': {
    methods: ["POST"],
    pattern: '/api/v1/game/places/sell',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"places"],[0,"sell"]],
    types: placeholder as Registry['game.places.sell']['types'],
  },
  'game.places.work': {
    methods: ["POST"],
    pattern: '/api/v1/game/places/work',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"places"],[0,"work"]],
    types: placeholder as Registry['game.places.work']['types'],
  },
  'game.places.service': {
    methods: ["POST"],
    pattern: '/api/v1/game/places/service',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"places"],[0,"service"]],
    types: placeholder as Registry['game.places.service']['types'],
  },
  'game.gather': {
    methods: ["POST"],
    pattern: '/api/v1/game/gather',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"gather"]],
    types: placeholder as Registry['game.gather']['types'],
  },
  'game.items.use': {
    methods: ["POST"],
    pattern: '/api/v1/game/items/use',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"items"],[0,"use"]],
    types: placeholder as Registry['game.items.use']['types'],
  },
  'game.craft': {
    methods: ["POST"],
    pattern: '/api/v1/game/craft',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"craft"]],
    types: placeholder as Registry['game.craft']['types'],
  },
  'game.jobs': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/game/jobs',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"jobs"]],
    types: placeholder as Registry['game.jobs']['types'],
  },
  'game.jobs.refresh': {
    methods: ["POST"],
    pattern: '/api/v1/game/jobs/refresh',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"jobs"],[0,"refresh"]],
    types: placeholder as Registry['game.jobs.refresh']['types'],
  },
  'game.jobs.accept': {
    methods: ["POST"],
    pattern: '/api/v1/game/jobs/:id/accept',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"jobs"],[1,"id"],[0,"accept"]],
    types: placeholder as Registry['game.jobs.accept']['types'],
  },
  'game.jobs.abandon': {
    methods: ["POST"],
    pattern: '/api/v1/game/jobs/:id/abandon',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"jobs"],[1,"id"],[0,"abandon"]],
    types: placeholder as Registry['game.jobs.abandon']['types'],
  },
  'game.jobs.step': {
    methods: ["POST"],
    pattern: '/api/v1/game/jobs/:id/step',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"jobs"],[1,"id"],[0,"step"]],
    types: placeholder as Registry['game.jobs.step']['types'],
  },
  'game.territory': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/game/territory',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"territory"]],
    types: placeholder as Registry['game.territory']['types'],
  },
  'game.territory.collect': {
    methods: ["POST"],
    pattern: '/api/v1/game/territory/collect',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"territory"],[0,"collect"]],
    types: placeholder as Registry['game.territory.collect']['types'],
  },
  'game.objects': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/game/objects',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"objects"]],
    types: placeholder as Registry['game.objects']['types'],
  },
  'game.objects.place': {
    methods: ["POST"],
    pattern: '/api/v1/game/objects',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"objects"]],
    types: placeholder as Registry['game.objects.place']['types'],
  },
  'game.objects.act': {
    methods: ["POST"],
    pattern: '/api/v1/game/objects/:id/act',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"objects"],[1,"id"],[0,"act"]],
    types: placeholder as Registry['game.objects.act']['types'],
  },
  'game.dev': {
    methods: ["POST"],
    pattern: '/api/v1/game/dev',
    tokens: [[0,"api"],[0,"v1"],[0,"game"],[0,"dev"]],
    types: placeholder as Registry['game.dev']['types'],
  },
  'map.map.config': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/map/config',
    tokens: [[0,"api"],[0,"v1"],[0,"map"],[0,"config"]],
    types: placeholder as Registry['map.map.config']['types'],
  },
  'map.map.chunk': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/map/chunks/:z/:x/:y',
    tokens: [[0,"api"],[0,"v1"],[0,"map"],[0,"chunks"],[1,"z"],[1,"x"],[1,"y"]],
    types: placeholder as Registry['map.map.chunk']['types'],
  },
  'time': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/time',
    tokens: [[0,"api"],[0,"v1"],[0,"time"]],
    types: placeholder as Registry['time']['types'],
  },
  'geo.geo.place': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/geo/place',
    tokens: [[0,"api"],[0,"v1"],[0,"geo"],[0,"place"]],
    types: placeholder as Registry['geo.geo.place']['types'],
  },
} as const satisfies Record<string, AdonisEndpoint>

export { routes }

export const registry = {
  routes,
  $tree: {} as ApiDefinition,
}

declare module '@tuyau/core/types' {
  export interface UserRegistry {
    routes: typeof routes
    $tree: ApiDefinition
  }
}
