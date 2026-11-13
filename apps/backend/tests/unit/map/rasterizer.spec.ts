import { test } from '@japa/runner'
import { BUILDING_GROUNDS, Ground, NO_PROP, Prop } from '#map/catalog'
import {
  ROOF_AXIS_Y,
  ROOF_TINT_SHIFT,
  RoofPart,
  SourceRasterizer,
  classifyBuilding,
  tileCenterLatitude,
} from '#map/rasterizer'
import { poiCategory } from '#map/poi_category'
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
    // Andén de 2,5 m a cada lado, y después el pasto.
    for (const row of [8, 12]) assert.equal(at(grid.ground, 30, row), Ground.PAVEMENT)
    for (const row of [6, 14]) assert.equal(at(grid.ground, 30, row), Ground.GRASS)
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
    assert.isTrue(BUILDING_GROUNDS.has(at(grid.ground, 5, 5)))
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
      { id: 'n3', kind: 'amenity:cafe', cat: 'food', name: 'Café Test', cell: [7, 8] },
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

  test('techos según el tipo de edificio, y variados entre vecinos', ({ assert }) => {
    assert.equal(classifyBuilding({ building: 'church' }, 'w1'), Ground.ROOF_CIVIC)
    assert.equal(classifyBuilding({ building: 'yes', amenity: 'school' }, 'w1'), Ground.ROOF_CIVIC)
    assert.equal(classifyBuilding({ building: 'warehouse' }, 'w1'), Ground.ROOF_INDUSTRIAL)
    assert.include(
      [Ground.ROOF_CONCRETE, Ground.ROOF_DARK],
      classifyBuilding({ 'building': 'apartments', 'building:levels': '12' }, 'w1')
    )
    assert.include(
      [Ground.ROOF_CONCRETE, Ground.ROOF_DARK],
      classifyBuilding({ building: 'yes', shop: 'supermarket' }, 'w1')
    )
    // Una manzana de building=yes no queda de un solo color.
    const roofs = new Set(
      Array.from({ length: 40 }, (_, i) => classifyBuilding({ building: 'yes' }, `w${i}`))
    )
    assert.isAtLeast(roofs.size, 3)
    // Determinista
    assert.equal(
      classifyBuilding({ building: 'yes' }, 'w7'),
      classifyBuilding({ building: 'yes' }, 'w7')
    )
  })

  test('pasos de cebra solo sobre el asfalto; vías férreas y ciclorrutas', ({ assert }) => {
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
      {
        kind: 'point',
        id: 'n1',
        tags: { highway: 'crossing', crossing: 'marked' },
        coord: localToLonLat(C, 30.5, 20.5),
      },
      {
        kind: 'line',
        id: 'w2',
        tags: { railway: 'rail' },
        coords: line(C, [
          [10.5, 30],
          [10.5, 63],
        ]),
      },
      {
        kind: 'line',
        id: 'w3',
        tags: { highway: 'cycleway' },
        coords: line(C, [
          [40.5, 30],
          [40.5, 63],
        ]),
      },
    ])
    assert.equal(at(grid.ground, 30, 20), Ground.CROSSWALK)
    assert.equal(at(grid.ground, 30, 18), Ground.PAVEMENT, 'el andén no se vuelve paso de cebra')
    assert.equal(at(grid.ground, 10, 45), Ground.RAIL)
    assert.equal(at(grid.ground, 40, 45), Ground.CYCLEWAY)
  })

  test('el andén no se pinta sobre el agua', ({ assert }) => {
    const grid = rasterize([
      { kind: 'area', id: 'w1', tags: { natural: 'water' }, rings: [rect(C, 0, 0, 64, 64)] },
      {
        kind: 'line',
        id: 'w2',
        tags: { highway: 'residential', bridge: 'yes' },
        coords: line(C, [
          [0, 20.5],
          [63, 20.5],
        ]),
      },
    ])
    assert.equal(at(grid.ground, 30, 20), Ground.ASPHALT)
    assert.equal(at(grid.ground, 30, 17), Ground.WATER)
  })

  test('mobiliario urbano: el semáforo de la calzada se pone en el andén', ({ assert }) => {
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
      {
        kind: 'point',
        id: 'n1',
        tags: { highway: 'traffic_signals' },
        coord: localToLonLat(C, 30.5, 20.5),
      },
      { kind: 'point', id: 'n2', tags: { amenity: 'bench' }, coord: localToLonLat(C, 5.5, 40.5) },
      {
        kind: 'point',
        id: 'n3',
        tags: { historic: 'memorial' },
        coord: localToLonLat(C, 50.5, 40.5),
      },
    ])
    const lights = Array.from(grid.props)
      .map((p, i) => [p, i] as const)
      .filter(([p]) => p === Prop.TRAFFIC_LIGHT)
    assert.lengthOf(lights, 1)
    assert.equal(grid.ground[lights[0][1]], Ground.PAVEMENT)
    assert.equal(at(grid.props, 5, 40), Prop.BENCH)
    assert.equal(at(grid.props, 50, 40), Prop.STATUE)
  })

  test('hileras de árboles y locales mapeados como edificio', ({ assert }) => {
    const grid = rasterize([
      {
        kind: 'line',
        id: 'w1',
        tags: { natural: 'tree_row' },
        coords: line(C, [
          [2.5, 50.5],
          [62.5, 50.5],
        ]),
      },
      {
        kind: 'area',
        id: 'w2',
        tags: { building: 'yes', shop: 'bakery', name: 'Panadería La Espiga' },
        rings: [rect(C, 20, 10, 30, 16)],
      },
    ])
    const trees = Array.from({ length: 64 }, (_, x) => at(grid.props, x, 50)).filter(
      (p) => p === Prop.TREE
    )
    assert.isAbove(trees.length, 10) // ~110 m de hilera, un árbol cada 7 m
    assert.lengthOf(grid.pois, 1)
    assert.equal(grid.pois[0].name, 'Panadería La Espiga')
    assert.equal(grid.pois[0].cat, 'food')
    assert.closeTo(grid.pois[0].cell[0], 25, 1)
    // El pin queda en la entrada (al frente del edificio), no dentro de él.
    const [px, py] = grid.pois[0].cell
    assert.isFalse(BUILDING_GROUNDS.has(at(grid.ground, px, py)))
    assert.equal(py, 16)
  })

  test('pisos de cada edificio: de OSM, por altura o típicos según el tipo', ({ assert }) => {
    const building = (id: string, x: number, tags: Record<string, string>): Feature => ({
      kind: 'area',
      id,
      tags: { building: 'yes', ...tags },
      rings: [rect(C, x, 10, x + 6, 16)],
    })
    const grid = rasterize([
      building('w1', 2, { 'building:levels': '7' }),
      building('w2', 12, { height: '13.5' }),
      building('w3', 22, { building: 'warehouse' }),
      building('w4', 32, { building: 'house' }),
    ])
    assert.equal(at(grid.levels, 4, 12), 7)
    assert.equal(at(grid.levels, 14, 12), 5) // 13,5 m / 3 m por piso
    assert.equal(at(grid.levels, 24, 12), 1) // bodega
    assert.oneOf(at(grid.levels, 34, 12), [1, 2, 3]) // casa sin datos
    assert.equal(at(grid.levels, 4, 30), 0, 'fuera de los edificios: 0')
    // Todas las celdas de un edificio tienen los mismos pisos.
    const w4 = new Set([at(grid.levels, 33, 11), at(grid.levels, 36, 14), at(grid.levels, 34, 12)])
    assert.equal(w4.size, 1)
  })

  test('categorías de POI', ({ assert }) => {
    assert.equal(poiCategory({ amenity: 'pharmacy' }), 'health')
    assert.equal(poiCategory({ shop: 'clothes' }), 'shop')
    assert.equal(poiCategory({ tourism: 'museum' }), 'culture')
    assert.equal(poiCategory({ amenity: 'place_of_worship' }), 'worship')
    assert.equal(poiCategory({ office: 'lawyer' }), 'service')
    assert.equal(poiCategory({ amenity: 'loquesea' }), 'other')
  })
})

test.group('Map rasterizer: techos', () => {
  const part = (b: number) => b & 3
  const axisY = (b: number) => (b & ROOF_AXIS_Y) !== 0
  const tint = (b: number) => b >> ROOF_TINT_SHIFT

  test('casa ancha en x: cumbrera a lo largo de x, faldones a cada lado', ({ assert }) => {
    const grid = rasterize([
      { kind: 'area', id: 'w1', tags: { building: 'house' }, rings: [rect(C, 10, 10, 20, 15)] },
    ])
    // 5 celdas de ancho en y (filas 10-14): cumbrera en la fila del medio.
    assert.equal(part(at(grid.roofs, 15, 10)), RoofPart.SLOPE_LOW)
    assert.equal(part(at(grid.roofs, 15, 11)), RoofPart.SLOPE_LOW)
    assert.equal(part(at(grid.roofs, 15, 12)), RoofPart.RIDGE)
    assert.equal(part(at(grid.roofs, 15, 14)), RoofPart.SLOPE_HIGH)
    assert.isFalse(axisY(at(grid.roofs, 15, 12)))
    // Mismo tono en todo el edificio; fuera del edificio, 0.
    assert.equal(tint(at(grid.roofs, 11, 10)), tint(at(grid.roofs, 19, 14)))
    assert.equal(at(grid.roofs, 30, 30), 0)
  })

  test('casa alta en y: cumbrera a lo largo de y', ({ assert }) => {
    const grid = rasterize([
      { kind: 'area', id: 'w1', tags: { building: 'house' }, rings: [rect(C, 10, 10, 13, 20)] },
    ])
    assert.isTrue(axisY(at(grid.roofs, 11, 15)))
    assert.equal(part(at(grid.roofs, 10, 15)), RoofPart.SLOPE_LOW)
    assert.equal(part(at(grid.roofs, 11, 15)), RoofPart.RIDGE)
    assert.equal(part(at(grid.roofs, 12, 15)), RoofPart.SLOPE_HIGH)
  })

  test('edificios anchos, de oficinas o bodegas: techo plano', ({ assert }) => {
    const grid = rasterize([
      { kind: 'area', id: 'w1', tags: { building: 'house' }, rings: [rect(C, 2, 30, 40, 50)] },
      { kind: 'area', id: 'w2', tags: { building: 'warehouse' }, rings: [rect(C, 45, 2, 50, 6)] },
    ])
    assert.equal(part(at(grid.roofs, 20, 40)), RoofPart.FLAT)
    assert.equal(part(at(grid.roofs, 47, 4)), RoofPart.FLAT)
  })
})
