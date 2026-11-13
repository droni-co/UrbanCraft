import '@adonisjs/core/types/http'

type ParamValue = string | number | bigint | boolean

export type ScannedRoutes = {
  ALL: {
    'play': { paramsTuple?: []; params?: {} }
    'play.file': { paramsTuple: [...ParamValue[]]; params: {'*': ParamValue[]} }
    'google_browser.redirect': { paramsTuple?: []; params?: {} }
    'google_browser.callback': { paramsTuple?: []; params?: {} }
    'auth.new_account.store': { paramsTuple?: []; params?: {} }
    'auth.access_tokens.store': { paramsTuple?: []; params?: {} }
    'auth.google.start': { paramsTuple?: []; params?: {} }
    'auth.google.poll': { paramsTuple?: []; params?: {} }
    'auth.methods': { paramsTuple?: []; params?: {} }
    'auth.dev.login': { paramsTuple?: []; params?: {} }
    'profile.profile.show': { paramsTuple?: []; params?: {} }
    'profile.profile.update': { paramsTuple?: []; params?: {} }
    'profile.access_tokens.destroy': { paramsTuple?: []; params?: {} }
    'player.stats': { paramsTuple?: []; params?: {} }
    'player.heartbeat': { paramsTuple?: []; params?: {} }
    'player.stats.dev': { paramsTuple?: []; params?: {} }
    'friends.index': { paramsTuple?: []; params?: {} }
    'friends.search': { paramsTuple?: []; params?: {} }
    'friends.requests.store': { paramsTuple?: []; params?: {} }
    'friends.requests.accept': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'friends.requests.reject': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'friends.location': { paramsTuple: [ParamValue]; params: {'userId': ParamValue} }
    'friends.destroy': { paramsTuple: [ParamValue]; params: {'userId': ParamValue} }
    'map.map.config': { paramsTuple?: []; params?: {} }
    'map.map.chunk': { paramsTuple: [ParamValue,ParamValue,ParamValue]; params: {'z': ParamValue,'x': ParamValue,'y': ParamValue} }
    'time': { paramsTuple?: []; params?: {} }
    'geo.geo.place': { paramsTuple?: []; params?: {} }
    'geo.geo.ip': { paramsTuple?: []; params?: {} }
  }
  GET: {
    'play': { paramsTuple?: []; params?: {} }
    'play.file': { paramsTuple: [...ParamValue[]]; params: {'*': ParamValue[]} }
    'google_browser.redirect': { paramsTuple?: []; params?: {} }
    'google_browser.callback': { paramsTuple?: []; params?: {} }
    'auth.methods': { paramsTuple?: []; params?: {} }
    'profile.profile.show': { paramsTuple?: []; params?: {} }
    'player.stats': { paramsTuple?: []; params?: {} }
    'friends.index': { paramsTuple?: []; params?: {} }
    'friends.search': { paramsTuple?: []; params?: {} }
    'friends.location': { paramsTuple: [ParamValue]; params: {'userId': ParamValue} }
    'map.map.config': { paramsTuple?: []; params?: {} }
    'map.map.chunk': { paramsTuple: [ParamValue,ParamValue,ParamValue]; params: {'z': ParamValue,'x': ParamValue,'y': ParamValue} }
    'time': { paramsTuple?: []; params?: {} }
    'geo.geo.place': { paramsTuple?: []; params?: {} }
    'geo.geo.ip': { paramsTuple?: []; params?: {} }
  }
  HEAD: {
    'play': { paramsTuple?: []; params?: {} }
    'play.file': { paramsTuple: [...ParamValue[]]; params: {'*': ParamValue[]} }
    'google_browser.redirect': { paramsTuple?: []; params?: {} }
    'google_browser.callback': { paramsTuple?: []; params?: {} }
    'auth.methods': { paramsTuple?: []; params?: {} }
    'profile.profile.show': { paramsTuple?: []; params?: {} }
    'player.stats': { paramsTuple?: []; params?: {} }
    'friends.index': { paramsTuple?: []; params?: {} }
    'friends.search': { paramsTuple?: []; params?: {} }
    'friends.location': { paramsTuple: [ParamValue]; params: {'userId': ParamValue} }
    'map.map.config': { paramsTuple?: []; params?: {} }
    'map.map.chunk': { paramsTuple: [ParamValue,ParamValue,ParamValue]; params: {'z': ParamValue,'x': ParamValue,'y': ParamValue} }
    'time': { paramsTuple?: []; params?: {} }
    'geo.geo.place': { paramsTuple?: []; params?: {} }
    'geo.geo.ip': { paramsTuple?: []; params?: {} }
  }
  POST: {
    'auth.new_account.store': { paramsTuple?: []; params?: {} }
    'auth.access_tokens.store': { paramsTuple?: []; params?: {} }
    'auth.google.start': { paramsTuple?: []; params?: {} }
    'auth.google.poll': { paramsTuple?: []; params?: {} }
    'auth.dev.login': { paramsTuple?: []; params?: {} }
    'profile.access_tokens.destroy': { paramsTuple?: []; params?: {} }
    'player.heartbeat': { paramsTuple?: []; params?: {} }
    'player.stats.dev': { paramsTuple?: []; params?: {} }
    'friends.requests.store': { paramsTuple?: []; params?: {} }
    'friends.requests.accept': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
  }
  PATCH: {
    'profile.profile.update': { paramsTuple?: []; params?: {} }
  }
  DELETE: {
    'friends.requests.reject': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'friends.destroy': { paramsTuple: [ParamValue]; params: {'userId': ParamValue} }
  }
}
declare module '@adonisjs/core/types/http' {
  export interface RoutesList extends ScannedRoutes {}
}