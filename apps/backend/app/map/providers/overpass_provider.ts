import type { BBox } from '#map/geo'
import type { FeatureSet } from '#map/features'
import { OsmProvider, OsmProviderError } from '#map/providers/osm_provider'
import { parseOverpass, type OverpassResponse } from '#map/providers/overpass_parser'

export interface OverpassOptions {
  url: string
  timeoutSeconds: number
  userAgent: string
}

/** Lo que se pide de cada source tile (cada línea lleva el bbox del tile). */
const SELECTORS = [
  'way[highway]',
  'way[building]',
  'relation[building][type=multipolygon]',
  'way[natural]',
  'relation[natural][type=multipolygon]',
  'way[landuse]',
  'relation[landuse][type=multipolygon]',
  'way[leisure]',
  'relation[leisure][type=multipolygon]',
  'way[waterway]',
  'way[amenity=parking]',
  'way[place=square]',
  'way["area:highway"]',
  'way[railway~"^(rail|light_rail|tram|narrow_gauge|monorail)$"]',
  'way[name][~"^(amenity|shop|tourism|historic|office|craft)$"~"."]',
  'node[natural=tree]',
  'node["addr:housenumber"]',
  'node[name][~"^(amenity|shop|tourism|leisure|historic|office|craft)$"~"."]',
  'node[highway~"^(bus_stop|traffic_signals|street_lamp|crossing)$"]',
  'node[amenity~"^(bench|fountain)$"]',
  'node[historic~"^(memorial|monument|statue)$"]',
  'node[tourism=artwork]',
]

/**
 * Los barrios son un punto (no un área): se buscan con más margen para que cada
 * chunk sepa en cuál está aunque el punto caiga en otro source tile (~1,6 km).
 */
const DISTRICT_SELECTOR = 'node[place~"^(suburb|neighbourhood|quarter)$"][name]'
const DISTRICT_MARGIN_DEGREES = 0.015

const bboxText = (...v: number[]) => v.map((n) => Number(n.toFixed(7))).join(',')

/**
 * Proveedor basado en la API Overpass.
 *
 * Las instancias públicas son lentas (30-60 s por km²) y limitan el uso por IP,
 * por eso: cada source tile se pide UNA sola vez (luego se reutiliza desde la
 * BD), las peticiones se serializan (worker con concurrencia 1) y para
 * producción se recomienda una instancia propia o el import local a PostGIS.
 */
export class OverpassProvider extends OsmProvider {
  readonly name = 'overpass'

  constructor(private options: OverpassOptions) {
    super()
  }

  /**
   * Ojo: sin [bbox:...] global. Overpass lo INTERSECTA con el bbox propio de
   * cada línea, así que no se podría pedir nada más allá del tile. Por eso
   * cada línea lleva su bbox y la geometría se recorta al tile en el `out`.
   */
  buildQuery(bbox: BBox): string {
    const b = bboxText(bbox.south, bbox.west, bbox.north, bbox.east)
    const m = DISTRICT_MARGIN_DEGREES
    const near = bboxText(bbox.south - m, bbox.west - m, bbox.north + m, bbox.east + m)
    return `[out:json][timeout:${this.options.timeoutSeconds}];
(
${SELECTORS.map((s) => `  ${s}(${b});`).join('\n')}
);
out geom(${b});
${DISTRICT_SELECTOR}(${near});
out;`
  }

  async fetchFeatures(bbox: BBox): Promise<FeatureSet> {
    let response: Response
    try {
      response = await fetch(this.options.url, {
        method: 'POST',
        body: new URLSearchParams({ data: this.buildQuery(bbox) }),
        headers: { 'User-Agent': this.options.userAgent, 'Accept': 'application/json' },
        signal: AbortSignal.timeout((this.options.timeoutSeconds + 15) * 1000),
      })
    } catch (error) {
      throw new OsmProviderError(`Overpass no respondió: ${(error as Error).message}`, true)
    }

    if (!response.ok) {
      const retryable = response.status === 429 || response.status >= 500
      throw new OsmProviderError(`Overpass HTTP ${response.status}`, retryable)
    }

    let json: OverpassResponse
    try {
      json = (await response.json()) as OverpassResponse
    } catch {
      throw new OsmProviderError('Overpass devolvió una respuesta no JSON', true)
    }

    // Overpass responde 200 con un "remark" cuando la consulta excede tiempo/memoria:
    // en ese caso los datos están incompletos y NO deben guardarse.
    if (json.remark && /error|timed out|out of memory/i.test(json.remark)) {
      throw new OsmProviderError(`Overpass incompleto: ${json.remark}`, true)
    }

    return parseOverpass(json)
  }
}
