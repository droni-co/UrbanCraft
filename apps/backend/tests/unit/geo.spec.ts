import { test } from '@japa/runner'
import { parseNominatimAddress } from '#geo/providers/nominatim_geocoder'

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
})
