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
  'geo.geo.ip': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/geo/ip',
    tokens: [[0,"api"],[0,"v1"],[0,"geo"],[0,"ip"]],
    types: placeholder as Registry['geo.geo.ip']['types'],
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
