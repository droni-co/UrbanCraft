import { test } from '@japa/runner'
import { Ground, NO_PROP, Prop } from '#map/catalog'
import { SourceRasterizer, tileCenterLatitude } from '#map/rasterizer'
import {
  CELL_ZOOM,
  CHUNK_SIZE,
  CHUNK_ZOOM,
  TEST_CHUNK,
  featureSet,
  line,
  localToLonLat,
  rect,
} from '#tests/helpers/map'
import type { Feature } from '#map/features'

const C = TEST_CHUNK
const at = (arr: Uint8Array, x: number, y: number) => arr[y * CHUNK_SIZE + x]

function rasterize(features: Feature[]) {
  const r = new SourceRasterizer(
    featureSet(features),
    { cellZoom: CELL_ZOOM, chunkZoom: CHUNK_ZOOM },
    tileCenterLatitude(CHUNK_ZOOM, C.y)
  )
  return r.rasterizeChunk(C.z, C.x, C.y)
}

test.group('Map rasterizer', () => {
  test('suelo por defecto es pasto y el tamaño es 64x64', ({ assert }) => {
    const grid = rasterize([])
    assert.equal(grid.size, 64)
    assert.lengthOf(grid.ground, 64 * 64)
    assert.isTrue(grid.ground.every((g) => g === Ground.GRASS))
  })

  test('una calle residencial se pinta con su ancho', ({ assert }) => {
    const grid = rasterize([
      {
        kind: 'line',
        id: 'w1',
        tags: { highway: 'residential' },
        coords: line(C, [
          [-5, 10.5],
          [70, 10.5],
        ]),
      },
    ])
    // 7 m a ~1.82 m/celda => semiancho ~1.9 celdas => filas 9, 10 y 11
    for (const row of [9, 10, 11]) assert.equal(at(grid.ground, 30, row), Ground.ASPHALT)
    for (const row of [7, 13]) assert.equal(at(grid.ground, 30, row), Ground.GRASS)
  })

  test('relleno de áreas y huecos de multipolígonos (par-impar)', ({ assert }) => {
    const grid = rasterize([
      { kind: 'area', id: 'w1', tags: { natural: 'water' }, rings: [rect(C, 40, 40, 50, 50)] },
      {
        kind: 'area',
        id: 'r1',
        tags: { natural: 'sand' },
        rings: [rect(C, 10, 30, 30, 50), rect(C, 18, 38, 22, 42)],
      },
    ])
    assert.equal(at(grid.ground, 45, 45), Ground.WATER)
    assert.equal(at(grid.ground, 39, 45), Ground.GRASS)
    assert.equal(at(grid.ground, 12, 32), Ground.SAND)
    assert.equal(at(grid.ground, 20, 40), Ground.GRASS, 'hueco interior')
  })

  test('prioridades: puente sobre agua y túneles ignorados', ({ assert }) => {
    const grid = rasterize([
      {
        kind: 'line',
        id: 'w2',
        tags: { highway: 'primary' },
        coords: line(C, [
          [45, 30],
          [45, 60],
        ]),
      },
      { kind: 'area', id: 'w1', tags: { natural: 'water' }, rings: [rect(C, 40, 40, 50, 50)] },
      {
        kind: 'line',
        id: 'w3',
        tags: { highway: 'primary', tunnel: 'yes' },
        coords: line(C, [
          [0, 5],
          [63, 5],
        ]),
      },
    ])
    assert.equal(at(grid.ground, 45, 45), Ground.ASPHALT, 'la calle queda encima del agua')
    // primary 13 m => semiancho ~3.6 celdas: las celdas 42-48 son calle, la 40 sigue siendo agua
    assert.equal(at(grid.ground, 42, 45), Ground.ASPHALT)
    assert.equal(at(grid.ground, 40, 45), Ground.WATER)
    assert.equal(at(grid.ground, 10, 5), Ground.GRASS, 'túnel no se dibuja')
  })

  test('edificios más chicos que una celda ocupan al menos una', ({ assert }) => {
    const grid = rasterize([
      { kind: 'area', id: 'w1', tags: { building: 'yes' }, rings: [rect(C, 5.2, 5.2, 5.4, 5.4)] },
    ])
    assert.equal(at(grid.ground, 5, 5), Ground.BUILDING)
  })

  test('senderos diagonales angostos quedan 4-conectados (transitables)', ({ assert }) => {
    const grid = rasterize([
      {
        kind: 'line',
        id: 'w1',
        tags: { highway: 'footway' },
        coords: line(C, [
          [2.5, 2.5],
          [60.5, 50.5],
        ]),
      },
    ])
    const isPath = (x: number, y: number) => at(grid.ground, x, y) === Ground.PAVEMENT
    assert.isTrue(isPath(2, 2) && isPath(60, 50))
    const seen = new Set(['2,2'])
    const queue = [[2, 2]]
    while (queue.length) {
      const [x, y] = queue.shift()!
      for (const [dx, dy] of [
        [1, 0],
        [-1, 0],
        [0, 1],
        [0, -1],
      ]) {
        const [nx, ny] = [x + dx, y + dy]
        const key = `${nx},${ny}`
        if (nx < 0 || ny < 0 || nx >= 64 || ny >= 64 || seen.has(key) || !isPath(nx, ny)) continue
        seen.add(key)
        queue.push([nx, ny])
      }
    }
    assert.isTrue(seen.has('60,50'))
  })

  test('árboles OSM solo sobre suelo natural y POIs con nombre', ({ assert }) => {
    const grid = rasterize([
      {
        kind: 'line',
        id: 'w1',
        tags: { highway: 'residential' },
        coords: line(C, [
          [0, 20.5],
          [63, 20.5],
        ]),
      },
      { kind: 'point', id: 'n1', tags: { natural: 'tree' }, coord: localToLonLat(C, 10.5, 40.5) },
      { kind: 'point', id: 'n2', tags: { natural: 'tree' }, coord: localToLonLat(C, 10.5, 20.5) },
      {
        kind: 'point',
        id: 'n3',
        tags: { amenity: 'cafe', name: 'Café Test' },
        coord: localToLonLat(C, 7.5, 8.5),
      },
      { kind: 'point', id: 'n4', tags: { amenity: 'bench' }, coord: localToLonLat(C, 3.5, 3.5) },
    ])
    assert.equal(at(grid.props, 10, 40), Prop.TREE)
    assert.equal(at(grid.props, 10, 20), NO_PROP, 'no hay árboles sobre la calle')
    assert.deepEqual(grid.pois, [
      { id: 'n3', kind: 'amenity:cafe', name: 'Café Test', cell: [7, 8] },
    ])
  })

  test('es determinista y los bosques tienen árboles', ({ assert }) => {
    const features: Feature[] = [
      { kind: 'area', id: 'w1', tags: { natural: 'wood' }, rings: [rect(C, 0, 0, 64, 64)] },
    ]
    const a = rasterize(features)
    const b = rasterize(features)
    assert.deepEqual(Array.from(a.props), Array.from(b.props))
    const trees = Array.from(a.props).filter((p) => p === Prop.TREE || p === Prop.PINE).length
    assert.isAbove(trees, 64 * 64 * 0.15)
    assert.isBelow(trees, 64 * 64 * 0.3)
  })
})
