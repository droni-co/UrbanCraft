import '@adonisjs/core/types/http'

type ParamValue = string | number | bigint | boolean

export type ScannedRoutes = {
  ALL: {
    'auth.new_account.store': { paramsTuple?: []; params?: {} }
    'auth.access_tokens.store': { paramsTuple?: []; params?: {} }
    'profile.profile.show': { paramsTuple?: []; params?: {} }
    'profile.access_tokens.destroy': { paramsTuple?: []; params?: {} }
    'map.map.config': { paramsTuple?: []; params?: {} }
    'map.map.chunk': { paramsTuple: [ParamValue,ParamValue,ParamValue]; params: {'z': ParamValue,'x': ParamValue,'y': ParamValue} }
    'geo.geo.place': { paramsTuple?: []; params?: {} }
    'geo.geo.ip': { paramsTuple?: []; params?: {} }
  }
  GET: {
    'profile.profile.show': { paramsTuple?: []; params?: {} }
    'map.map.config': { paramsTuple?: []; params?: {} }
    'map.map.chunk': { paramsTuple: [ParamValue,ParamValue,ParamValue]; params: {'z': ParamValue,'x': ParamValue,'y': ParamValue} }
    'geo.geo.place': { paramsTuple?: []; params?: {} }
    'geo.geo.ip': { paramsTuple?: []; params?: {} }
  }
  HEAD: {
    'profile.profile.show': { paramsTuple?: []; params?: {} }
    'map.map.config': { paramsTuple?: []; params?: {} }
    'map.map.chunk': { paramsTuple: [ParamValue,ParamValue,ParamValue]; params: {'z': ParamValue,'x': ParamValue,'y': ParamValue} }
    'geo.geo.place': { paramsTuple?: []; params?: {} }
    'geo.geo.ip': { paramsTuple?: []; params?: {} }
  }
  POST: {
    'auth.new_account.store': { paramsTuple?: []; params?: {} }
    'auth.access_tokens.store': { paramsTuple?: []; params?: {} }
    'profile.access_tokens.destroy': { paramsTuple?: []; params?: {} }
  }
}
declare module '@adonisjs/core/types/http' {
  export interface RoutesList extends ScannedRoutes {}
}