import type { ApplicationService } from '@adonisjs/core/types'
import type { GeoConfig } from '#config/geo'
import { ChainIpLocator, IpLocator, IpapiLocator, IpwhoLocator } from '#geo/providers/ip_locator'
import { NominatimGeocoder } from '#geo/providers/nominatim_geocoder'
import { ReverseGeocoder } from '#geo/providers/reverse_geocoder'
import { GeoService } from '#services/geo_service'

/** Registra los proveedores de geolocalización (intercambiables en tests). */
export default class GeoProvider {
  constructor(protected app: ApplicationService) {}

  register() {
    const config = () => this.app.config.get<GeoConfig>('geo')

    this.app.container.singleton(ReverseGeocoder, () => new NominatimGeocoder(config().nominatim))
    this.app.container.singleton(IpLocator, () => {
      const { ip, nominatim } = config()
      const all = {
        ipapi: () => new IpapiLocator(nominatim.userAgent, ip.timeoutMs),
        ipwho: () => new IpwhoLocator(nominatim.userAgent, ip.timeoutMs),
      }
      return new ChainIpLocator(ip.providers.map((name) => all[name]()))
    })
    this.app.container.singleton(
      GeoService,
      async (resolver) =>
        new GeoService(
          config(),
          await resolver.make(ReverseGeocoder),
          await resolver.make(IpLocator)
        )
    )
  }
}
