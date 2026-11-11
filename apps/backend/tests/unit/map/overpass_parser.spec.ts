import { test } from '@japa/runner'
import { parseOverpass } from '#map/providers/overpass_parser'

const g = (pts: Array<[number, number]>) => pts.map(([lon, lat]) => ({ lat, lon }))

test.group('Overpass parser', () => {
  test('normaliza nodos, vías, áreas y multipolígonos', ({ assert }) => {
    const set = parseOverpass({
      osm3s: { timestamp_osm_base: '2026-11-11T00:00:00Z' },
      elements: [
        { type: 'node', id: 1, lat: 1, lon: 2, tags: { natural: 'tree', foo: 'bar' } },
        { type: 'node', id: 2, lat: 1, lon: 2 },
        {
          type: 'way',
          id: 10,
          tags: { building: 'yes' },
          geometry: g([
            [0, 0],
            [1, 0],
            [1, 1],
            [0, 0],
          ]),
        },
        {
          type: 'way',
          id: 11,
          tags: { highway: 'residential' },
          geometry: g([
            [0, 0],
            [1, 1],
          ]),
        },
        {
          type: 'way',
          id: 12,
          tags: { highway: 'primary', junction: 'roundabout' },
          geometry: g([
            [0, 0],
            [1, 0],
            [1, 1],
            [0, 0],
          ]),
        },
        {
          type: 'relation',
          id: 20,
          tags: { type: 'multipolygon', natural: 'water' },
          members: [
            {
              type: 'way',
              role: 'outer',
              geometry: g([
                [0, 0],
                [2, 0],
                [2, 2],
              ]),
            },
            {
              type: 'way',
              role: 'outer',
              geometry: g([
                [2, 2],
                [0, 2],
                [0, 0],
              ]),
            },
            { type: 'node', role: 'label' },
          ],
        },
        { type: 'relation', id: 21, tags: { type: 'route' }, members: [] },
      ],
    })

    assert.equal(set.osmTimestamp, '2026-11-11T00:00:00Z')
    const byId = Object.fromEntries(set.features.map((f) => [f.id, f]))
    assert.notProperty(byId, 'n2', 'nodos sin etiquetas se ignoran')
    assert.notProperty(byId, 'r21', 'solo relaciones multipolygon')

    assert.equal(byId.n1.kind, 'point')
    assert.deepEqual(byId.n1.tags, { natural: 'tree' }, 'descarta etiquetas no usadas')
    assert.equal(byId.w10.kind, 'area')
    assert.equal(byId.w11.kind, 'line')
    assert.equal(byId.w12.kind, 'line', 'una rotonda cerrada sigue siendo línea')
    assert.equal(byId.r20.kind, 'area')
    assert.lengthOf((byId.r20 as any).rings, 2)
  })
})
