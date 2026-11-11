import { test } from '@japa/runner'
import app from '@adonisjs/core/services/app'
import db from '@adonisjs/lucid/services/db'
import type { GeoConfig } from '#config/geo'
import { IpLocator } from '#geo/providers/ip_locator'
import { ReverseGeocoder } from '#geo/providers/reverse_geocoder'
import { GeoProviderError, type IpLocation, type Place } from '#geo/types'
import { GeoService } from '#services/geo_service'

class FakeGeocoder extends ReverseGeocoder {
  readonly name = 'fake'
  calls: Array<[number, number]> = []
  constructor(
    private place: Place | null,
    private fail = false
  ) {
    super()
  }
  async reverse(lat: number, lon: number) {
    this.calls.push([lat, lon])
    if (this.fail) throw new GeoProviderError('caído', true)
    return this.place
  }
}

class FakeIpLocator extends IpLocator {
  readonly name = 'fake'
  calls: Array<string | null> = []
  async locate(ip: string | null): Promise<IpLocation | null> {
    this.calls.push(ip)
    return {
      latitude: 4.6097,
      longitude: -74.0817,
      city: 'Bogotá',
      region: 'Bogotá D.C.',
      country: 'Colombia',
      countryCode: 'CO',
      accuracyKm: 10,
      provider: 'fake',
    }
  }
}

const MADRID: Place = {
  city: 'Madrid',
  region: 'Comunidad de Madrid',
  country: 'España',
  countryCode: 'ES',
  label: 'Madrid, España',
}

function setup(geocoder: FakeGeocoder, overrides: Partial<GeoConfig> = {}) {
  const base = app.config.get<GeoConfig>('geo')
  const config: GeoConfig = {
    ...base,
    ...overrides,
    nominatim: { ...base.nominatim, minIntervalMs: 0 },
  }
  const ip = new FakeIpLocator()
  app.container.swap(GeoService, () => new GeoService(config, geocoder, ip))
  return { ip }
}

test.group('Geo API', (group) => {
  group.each.setup(async () => {
    await db.rawQuery('TRUNCATE geo_places RESTART IDENTITY')
    return () => app.container.restore(GeoService)
  })

  test('ciudad y país por zona, consultando el centro del tile y cacheando', async ({
    client,
    assert,
  }) => {
    const geocoder = new FakeGeocoder(MADRID)
    setup(geocoder)

    const res = await client.get('/api/v1/geo/place').qs({ lat: '40.4200', lon: '-3.6887' })
    res.assertStatus(200)
    assert.equal(res.body().label, 'Madrid, España')
    assert.equal(res.body().countryCode, 'ES')

    // Otra posición en el mismo tile z14: no vuelve a consultar al proveedor.
    const again = await client.get('/api/v1/geo/place').qs({ lat: '40.4210', lon: '-3.6880' })
    again.assertStatus(200)
    assert.lengthOf(geocoder.calls, 1)

    // Se consulta el centro del tile, no la posición exacta del jugador.
    const [lat, lon] = geocoder.calls[0]
    assert.notEqual(lat, 40.42)
    assert.notEqual(lon, -3.6887)
    assert.closeTo(lat, 40.42, 0.02)
    assert.closeTo(lon, -3.6887, 0.02)

    // Persistido: un servicio nuevo (otro servidor) lo lee de la BD.
    const other = new FakeGeocoder(null)
    setup(other)
    const fromDb = await client.get('/api/v1/geo/place').qs({ lat: '40.4200', lon: '-3.6887' })
    assert.equal(fromDb.body().label, 'Madrid, España')
    assert.lengthOf(other.calls, 0)
  })

  test('valida coordenadas y responde 404 en zonas sin ciudad', async ({ client }) => {
    setup(new FakeGeocoder(null))
    const bad = await client.get('/api/v1/geo/place').qs({ lat: 'abc', lon: '1' })
    bad.assertStatus(422)
    const sea = await client.get('/api/v1/geo/place').qs({ lat: '0.5', lon: '-30' })
    sea.assertStatus(404)
  })

  test('503 si el proveedor falla, sin cachear el error', async ({ client, assert }) => {
    setup(new FakeGeocoder(MADRID, true))
    const res = await client.get('/api/v1/geo/place').qs({ lat: '40.42', lon: '-3.6887' })
    res.assertStatus(503)
    const { rows } = await db.rawQuery('SELECT count(*)::int AS n FROM geo_places')
    assert.equal(rows[0].n, 0)
  })

  test('ubicación por IP: aproximada; con IP local consulta la del servidor', async ({
    client,
    assert,
  }) => {
    const { ip } = setup(new FakeGeocoder(MADRID), {
      ip: { ...app.config.get<GeoConfig>('geo').ip, enabled: true },
    })
    const res = await client.get('/api/v1/geo/ip')
    res.assertStatus(200)
    assert.equal(res.body().city, 'Bogotá')
    assert.isTrue(res.body().approximate)
    assert.deepEqual(ip.calls, [null], 'localhost -> IP pública del propio servidor')
  })

  test('ubicación por IP desactivada responde 404', async ({ client }) => {
    setup(new FakeGeocoder(MADRID), {
      ip: { ...app.config.get<GeoConfig>('geo').ip, enabled: false },
    })
    const res = await client.get('/api/v1/geo/ip')
    res.assertStatus(404)
  })
})
