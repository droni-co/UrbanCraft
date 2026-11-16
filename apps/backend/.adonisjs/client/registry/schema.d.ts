/* eslint-disable prettier/prettier */
/// <reference path="../manifest.d.ts" />

import type { ExtractBody, ExtractErrorResponse, ExtractQuery, ExtractQueryForGet, ExtractRawResponse, ExtractResponse, Method, PathWithRegistry, PatternsByMethod, RouteWithRegistry } from '@tuyau/core/types'
import type { InferInput, SimpleError } from '@vinejs/vine/types'
import type { routes } from './index.ts'

export type ParamValue = string | number | bigint | boolean

export interface Registry {
  'play': {
    methods: ["GET","HEAD"]
    pattern: '/play'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/web_game_controller').default['index']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/web_game_controller').default['index']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/web_game_controller').default['index']>>>
    }
  }
  'play.file': {
    methods: ["GET","HEAD"]
    pattern: '/play/*'
    types: {
      body: {}
      paramsTuple: [ParamValue]
      params: { '*': ParamValue[] }
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/web_game_controller').default['file']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/web_game_controller').default['file']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/web_game_controller').default['file']>>>
    }
  }
  'google_browser.redirect': {
    methods: ["GET","HEAD"]
    pattern: '/auth/google/redirect'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/google_auth_controller').default['redirect']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/google_auth_controller').default['redirect']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/google_auth_controller').default['redirect']>>>
    }
  }
  'google_browser.callback': {
    methods: ["GET","HEAD"]
    pattern: '/auth/google/callback'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/google_auth_controller').default['callback']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/google_auth_controller').default['callback']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/google_auth_controller').default['callback']>>>
    }
  }
  'auth.new_account.store': {
    methods: ["POST"]
    pattern: '/api/v1/auth/signup'
    types: {
      body: ExtractBody<InferInput<(typeof import('#validators/user').signupValidator)>>
      paramsTuple: []
      params: {}
      query: ExtractQuery<InferInput<(typeof import('#validators/user').signupValidator)>>
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/new_account_controller').default['store']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/new_account_controller').default['store']>>> | { status: 422; response: { errors: SimpleError[] } }
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/new_account_controller').default['store']>>> | { status: 422; response: { errors: SimpleError[] } }
    }
  }
  'auth.access_tokens.store': {
    methods: ["POST"]
    pattern: '/api/v1/auth/login'
    types: {
      body: ExtractBody<InferInput<(typeof import('#validators/user').loginValidator)>>
      paramsTuple: []
      params: {}
      query: ExtractQuery<InferInput<(typeof import('#validators/user').loginValidator)>>
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/access_tokens_controller').default['store']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/access_tokens_controller').default['store']>>> | { status: 422; response: { errors: SimpleError[] } }
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/access_tokens_controller').default['store']>>> | { status: 422; response: { errors: SimpleError[] } }
    }
  }
  'auth.google.start': {
    methods: ["POST"]
    pattern: '/api/v1/auth/google/start'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/google_auth_controller').default['start']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/google_auth_controller').default['start']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/google_auth_controller').default['start']>>>
    }
  }
  'auth.google.poll': {
    methods: ["POST"]
    pattern: '/api/v1/auth/google/poll'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/google_auth_controller').default['poll']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/google_auth_controller').default['poll']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/google_auth_controller').default['poll']>>>
    }
  }
  'auth.methods': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/auth/methods'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/dev_login_controller').default['methods']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/dev_login_controller').default['methods']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/dev_login_controller').default['methods']>>>
    }
  }
  'auth.dev.login': {
    methods: ["POST"]
    pattern: '/api/v1/auth/dev/login'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/dev_login_controller').default['store']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/dev_login_controller').default['store']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/dev_login_controller').default['store']>>>
    }
  }
  'profile.profile.show': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/account/profile'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/profile_controller').default['show']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/profile_controller').default['show']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/profile_controller').default['show']>>>
    }
  }
  'profile.profile.update': {
    methods: ["PATCH"]
    pattern: '/api/v1/account/profile'
    types: {
      body: ExtractBody<InferInput<(typeof import('#validators/user').updateProfileValidator)>>
      paramsTuple: []
      params: {}
      query: ExtractQuery<InferInput<(typeof import('#validators/user').updateProfileValidator)>>
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/profile_controller').default['update']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/profile_controller').default['update']>>> | { status: 422; response: { errors: SimpleError[] } }
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/profile_controller').default['update']>>> | { status: 422; response: { errors: SimpleError[] } }
    }
  }
  'profile.access_tokens.destroy': {
    methods: ["POST"]
    pattern: '/api/v1/account/logout'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/access_tokens_controller').default['destroy']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/access_tokens_controller').default['destroy']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/access_tokens_controller').default['destroy']>>>
    }
  }
  'player.stats': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/player/stats'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/player_stats_controller').default['show']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/player_stats_controller').default['show']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/player_stats_controller').default['show']>>>
    }
  }
  'player.heartbeat': {
    methods: ["POST"]
    pattern: '/api/v1/player/heartbeat'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/player_stats_controller').default['heartbeat']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/player_stats_controller').default['heartbeat']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/player_stats_controller').default['heartbeat']>>>
    }
  }
  'player.stats.dev': {
    methods: ["POST"]
    pattern: '/api/v1/player/stats/dev'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/player_stats_controller').default['devUpdate']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/player_stats_controller').default['devUpdate']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/player_stats_controller').default['devUpdate']>>>
    }
  }
  'friends.index': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/friends'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['index']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['index']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['index']>>>
    }
  }
  'friends.search': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/friends/search'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['search']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['search']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['search']>>>
    }
  }
  'friends.requests.store': {
    methods: ["POST"]
    pattern: '/api/v1/friends/requests'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['store']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['store']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['store']>>>
    }
  }
  'friends.requests.accept': {
    methods: ["POST"]
    pattern: '/api/v1/friends/requests/:id/accept'
    types: {
      body: {}
      paramsTuple: [ParamValue]
      params: { id: ParamValue }
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['accept']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['accept']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['accept']>>>
    }
  }
  'friends.requests.reject': {
    methods: ["DELETE"]
    pattern: '/api/v1/friends/requests/:id'
    types: {
      body: {}
      paramsTuple: [ParamValue]
      params: { id: ParamValue }
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['reject']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['reject']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['reject']>>>
    }
  }
  'friends.location': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/friends/:userId/location'
    types: {
      body: {}
      paramsTuple: [ParamValue]
      params: { userId: ParamValue }
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['location']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['location']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['location']>>>
    }
  }
  'friends.destroy': {
    methods: ["DELETE"]
    pattern: '/api/v1/friends/:userId'
    types: {
      body: {}
      paramsTuple: [ParamValue]
      params: { userId: ParamValue }
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['destroy']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['destroy']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/friends_controller').default['destroy']>>>
    }
  }
  'game.catalog': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/game/catalog'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['catalog']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['catalog']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['catalog']>>>
    }
  }
  'game.state': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/game/state'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['state']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['state']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['state']>>>
    }
  }
  'game.story.seen': {
    methods: ["POST"]
    pattern: '/api/v1/game/story/seen'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['storySeen']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['storySeen']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['storySeen']>>>
    }
  }
  'game.story.talk': {
    methods: ["POST"]
    pattern: '/api/v1/game/story/talk'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['storyTalk']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['storyTalk']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['storyTalk']>>>
    }
  }
  'game.places.visit': {
    methods: ["POST"]
    pattern: '/api/v1/game/places/visit'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['visit']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['visit']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['visit']>>>
    }
  }
  'game.places.buy': {
    methods: ["POST"]
    pattern: '/api/v1/game/places/buy'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['buy']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['buy']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['buy']>>>
    }
  }
  'game.places.sell': {
    methods: ["POST"]
    pattern: '/api/v1/game/places/sell'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['sell']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['sell']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['sell']>>>
    }
  }
  'game.places.work': {
    methods: ["POST"]
    pattern: '/api/v1/game/places/work'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['work']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['work']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['work']>>>
    }
  }
  'game.places.service': {
    methods: ["POST"]
    pattern: '/api/v1/game/places/service'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['service']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['service']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['service']>>>
    }
  }
  'game.gather': {
    methods: ["POST"]
    pattern: '/api/v1/game/gather'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['gather']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['gather']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['gather']>>>
    }
  }
  'game.items.use': {
    methods: ["POST"]
    pattern: '/api/v1/game/items/use'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['use']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['use']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['use']>>>
    }
  }
  'game.craft': {
    methods: ["POST"]
    pattern: '/api/v1/game/craft'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['craft']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['craft']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['craft']>>>
    }
  }
  'game.jobs': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/game/jobs'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobs']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobs']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobs']>>>
    }
  }
  'game.jobs.refresh': {
    methods: ["POST"]
    pattern: '/api/v1/game/jobs/refresh'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobRefresh']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobRefresh']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobRefresh']>>>
    }
  }
  'game.jobs.accept': {
    methods: ["POST"]
    pattern: '/api/v1/game/jobs/:id/accept'
    types: {
      body: {}
      paramsTuple: [ParamValue]
      params: { id: ParamValue }
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobAccept']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobAccept']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobAccept']>>>
    }
  }
  'game.jobs.abandon': {
    methods: ["POST"]
    pattern: '/api/v1/game/jobs/:id/abandon'
    types: {
      body: {}
      paramsTuple: [ParamValue]
      params: { id: ParamValue }
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobAbandon']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobAbandon']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobAbandon']>>>
    }
  }
  'game.jobs.step': {
    methods: ["POST"]
    pattern: '/api/v1/game/jobs/:id/step'
    types: {
      body: {}
      paramsTuple: [ParamValue]
      params: { id: ParamValue }
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobStep']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobStep']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['jobStep']>>>
    }
  }
  'game.territory': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/game/territory'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['territory']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['territory']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['territory']>>>
    }
  }
  'game.territory.collect': {
    methods: ["POST"]
    pattern: '/api/v1/game/territory/collect'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['collectRent']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['collectRent']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['collectRent']>>>
    }
  }
  'game.objects': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/game/objects'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['objects']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['objects']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['objects']>>>
    }
  }
  'game.objects.place': {
    methods: ["POST"]
    pattern: '/api/v1/game/objects'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['placeObject']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['placeObject']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['placeObject']>>>
    }
  }
  'game.objects.act': {
    methods: ["POST"]
    pattern: '/api/v1/game/objects/:id/act'
    types: {
      body: {}
      paramsTuple: [ParamValue]
      params: { id: ParamValue }
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['objectAction']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['objectAction']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['objectAction']>>>
    }
  }
  'game.dev': {
    methods: ["POST"]
    pattern: '/api/v1/game/dev'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/game_controller').default['dev']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/game_controller').default['dev']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/game_controller').default['dev']>>>
    }
  }
  'map.map.config': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/map/config'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/map_controller').default['config']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/map_controller').default['config']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/map_controller').default['config']>>>
    }
  }
  'map.map.chunk': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/map/chunks/:z/:x/:y'
    types: {
      body: {}
      paramsTuple: [ParamValue, ParamValue, ParamValue]
      params: { z: ParamValue; x: ParamValue; y: ParamValue }
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/map_controller').default['chunk']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/map_controller').default['chunk']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/map_controller').default['chunk']>>>
    }
  }
  'time': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/time'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: unknown
      errorResponse: unknown
      rawResponse: ExtractRawResponse<unknown>
    }
  }
  'geo.geo.place': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/geo/place'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/geo_controller').default['place']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/geo_controller').default['place']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/geo_controller').default['place']>>>
    }
  }
  'geo.geo.ip': {
    methods: ["GET","HEAD"]
    pattern: '/api/v1/geo/ip'
    types: {
      body: {}
      paramsTuple: []
      params: {}
      query: {}
      response: ExtractResponse<Awaited<ReturnType<import('#controllers/geo_controller').default['ip']>>>
      errorResponse: ExtractErrorResponse<Awaited<ReturnType<import('#controllers/geo_controller').default['ip']>>>
      rawResponse: ExtractRawResponse<Awaited<ReturnType<import('#controllers/geo_controller').default['ip']>>>
    }
  }
}

export namespace Route {
  export type Request<Name extends keyof typeof routes> = RouteWithRegistry.Request<typeof routes, Name>
  export type Response<Name extends keyof typeof routes> = RouteWithRegistry.Response<typeof routes, Name>
  export type Params<Name extends keyof typeof routes> = RouteWithRegistry.Params<typeof routes, Name>
  export type Body<Name extends keyof typeof routes> = RouteWithRegistry.Body<typeof routes, Name>
  export type Query<Name extends keyof typeof routes> = RouteWithRegistry.Query<typeof routes, Name>
  export type Error<Name extends keyof typeof routes> = RouteWithRegistry.Error<typeof routes, Name>
}

export namespace Path {
  export type Request<M extends Method, P extends PatternsByMethod<typeof routes, M>> =
    PathWithRegistry.Request<typeof routes, M, P>
  export type Response<M extends Method, P extends PatternsByMethod<typeof routes, M>> =
    PathWithRegistry.Response<typeof routes, M, P>
  export type Params<M extends Method, P extends PatternsByMethod<typeof routes, M>> =
    PathWithRegistry.Params<typeof routes, M, P>
  export type Body<M extends Method, P extends PatternsByMethod<typeof routes, M>> =
    PathWithRegistry.Body<typeof routes, M, P>
  export type Query<M extends Method, P extends PatternsByMethod<typeof routes, M>> =
    PathWithRegistry.Query<typeof routes, M, P>
  export type Error<M extends Method, P extends PatternsByMethod<typeof routes, M>> =
    PathWithRegistry.Error<typeof routes, M, P>
}
