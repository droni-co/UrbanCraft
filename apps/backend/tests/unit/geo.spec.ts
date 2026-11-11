import { test } from '@japa/runner'
import { parseNominatimAddress } from '#geo/providers/nominatim_geocoder'
import { isPublicIp } from '#services/geo_service'

test.group('Geo', () => {
  test('arma ciudad y país desde la dirección de Nominatim', ({ assert }) => {
    assert.deepEqual(
      parseNominatimAddress({
        town: 'Cota',
        state: 'Cundinamarca',
        country: 'Colombia',
        country_code: 'co',
      }),
      {
        city: 'Cota',
        region: 'Cundinamarca',
        country: 'Colombia',
        countryCode: 'CO',
        label: 'Cota, Colombia',
      }
    )
    assert.equal(
      parseNominatimAddress({ city: 'Singapur', country: 'Singapur' })!.label,
      'Singapur'
    )
    assert.equal(parseNominatimAddress({ state: 'Antártida' })!.label, 'Antártida')
    assert.isNull(parseNominatimAddress({}))
  })

  test('distingue IPs públicas de locales y privadas', ({ assert }) => {
    for (const ip of [
      '127.0.0.1',
      '::1',
      '10.1.2.3',
      '192.168.0.5',
      '172.20.0.1',
      '::ffff:127.0.0.1',
      'fd00::1',
      '100.64.0.1',
    ]) {
      assert.isFalse(isPublicIp(ip), ip)
    }
    for (const ip of ['8.8.8.8', '181.49.10.20', '2001:4860:4860::8888']) {
      assert.isTrue(isPublicIp(ip), ip)
    }
  })
})
