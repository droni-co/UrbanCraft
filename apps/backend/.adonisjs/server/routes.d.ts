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
    'players.show': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'game.catalog': { paramsTuple?: []; params?: {} }
    'game.state': { paramsTuple?: []; params?: {} }
    'game.story.seen': { paramsTuple?: []; params?: {} }
    'game.story.talk': { paramsTuple?: []; params?: {} }
    'game.places.visit': { paramsTuple?: []; params?: {} }
    'game.places.buy': { paramsTuple?: []; params?: {} }
    'game.places.sell': { paramsTuple?: []; params?: {} }
    'game.places.work': { paramsTuple?: []; params?: {} }
    'game.places.service': { paramsTuple?: []; params?: {} }
    'game.gather': { paramsTuple?: []; params?: {} }
    'game.items.use': { paramsTuple?: []; params?: {} }
    'game.craft': { paramsTuple?: []; params?: {} }
    'game.jobs': { paramsTuple?: []; params?: {} }
    'game.jobs.refresh': { paramsTuple?: []; params?: {} }
    'game.jobs.accept': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'game.jobs.abandon': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'game.jobs.step': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'game.territory': { paramsTuple?: []; params?: {} }
    'game.territory.collect': { paramsTuple?: []; params?: {} }
    'game.objects': { paramsTuple?: []; params?: {} }
    'game.objects.place': { paramsTuple?: []; params?: {} }
    'game.objects.act': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'game.dev': { paramsTuple?: []; params?: {} }
    'map.map.config': { paramsTuple?: []; params?: {} }
    'map.map.chunk': { paramsTuple: [ParamValue,ParamValue,ParamValue]; params: {'z': ParamValue,'x': ParamValue,'y': ParamValue} }
    'time': { paramsTuple?: []; params?: {} }
    'geo.geo.place': { paramsTuple?: []; params?: {} }
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
    'players.show': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'game.catalog': { paramsTuple?: []; params?: {} }
    'game.state': { paramsTuple?: []; params?: {} }
    'game.jobs': { paramsTuple?: []; params?: {} }
    'game.territory': { paramsTuple?: []; params?: {} }
    'game.objects': { paramsTuple?: []; params?: {} }
    'map.map.config': { paramsTuple?: []; params?: {} }
    'map.map.chunk': { paramsTuple: [ParamValue,ParamValue,ParamValue]; params: {'z': ParamValue,'x': ParamValue,'y': ParamValue} }
    'time': { paramsTuple?: []; params?: {} }
    'geo.geo.place': { paramsTuple?: []; params?: {} }
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
    'players.show': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'game.catalog': { paramsTuple?: []; params?: {} }
    'game.state': { paramsTuple?: []; params?: {} }
    'game.jobs': { paramsTuple?: []; params?: {} }
    'game.territory': { paramsTuple?: []; params?: {} }
    'game.objects': { paramsTuple?: []; params?: {} }
    'map.map.config': { paramsTuple?: []; params?: {} }
    'map.map.chunk': { paramsTuple: [ParamValue,ParamValue,ParamValue]; params: {'z': ParamValue,'x': ParamValue,'y': ParamValue} }
    'time': { paramsTuple?: []; params?: {} }
    'geo.geo.place': { paramsTuple?: []; params?: {} }
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
    'game.story.seen': { paramsTuple?: []; params?: {} }
    'game.story.talk': { paramsTuple?: []; params?: {} }
    'game.places.visit': { paramsTuple?: []; params?: {} }
    'game.places.buy': { paramsTuple?: []; params?: {} }
    'game.places.sell': { paramsTuple?: []; params?: {} }
    'game.places.work': { paramsTuple?: []; params?: {} }
    'game.places.service': { paramsTuple?: []; params?: {} }
    'game.gather': { paramsTuple?: []; params?: {} }
    'game.items.use': { paramsTuple?: []; params?: {} }
    'game.craft': { paramsTuple?: []; params?: {} }
    'game.jobs.refresh': { paramsTuple?: []; params?: {} }
    'game.jobs.accept': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'game.jobs.abandon': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'game.jobs.step': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'game.territory.collect': { paramsTuple?: []; params?: {} }
    'game.objects.place': { paramsTuple?: []; params?: {} }
    'game.objects.act': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'game.dev': { paramsTuple?: []; params?: {} }
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