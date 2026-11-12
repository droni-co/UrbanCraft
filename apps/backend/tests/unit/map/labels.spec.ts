import { test } from '@japa/runner'
import { clipPolyline, interiorPoint, longestStraightRun } from '#map/labels'
import { SourceRasterizer, tileCenterLatitude } from '#map/rasterizer'
import type { Feature } from '#map/features'
import {
  CELL_ZOOM,
  CHUNK_ZOOM,
  TEST_CHUNK,
  featureSet,
  line,
  localToLonLat,
  rect,
} from '#tests/helpers/map'

const C = TEST_CHUNK

function labelsOf(features: Feature[], chunk = C) {
  const r = new SourceRasterizer(
    featureSet(features),
    { cellZoom: CELL_ZOOM, chunkZoom: CHUNK_ZOOM },
    tileCenterLatitude(CHUNK_ZOOM, C.y)
  )
  return r.rasterizeChunk(chunk.z, chunk.x, chunk.y).labels
}

test.group('Map labels · geometría', () => {
  test('recorta una polilínea al rectángulo en trozos continuos', ({ assert }) => {
    // Entra, sale y vuelve a entrar en [0,10]x[0,10].
    const pieces = clipPolyline(Float64Array.from([-5, 5, 5, 5, 15, 5, 15, 8, 5, 8]), 0, 0, 10, 10)
    assert.lengthOf(pieces, 2)
    assert.deepEqual(Array.from(pieces[0]), [0, 5, 5, 5, 10, 5])
    assert.deepEqual(Array.from(pieces[1]), [10, 8, 5, 8])
  })

  test('el tramo recto más largo ignora la parte curva', ({ assert }) => {
    // 4 celdas al este, luego 20 al sur.
    const run = longestStraightRun(Float64Array.from([0, 0, 4, 0, 4, 20]))!
    assert.closeTo(run.length, 20, 1e-9)
    assert.closeTo(run.angle, Math.PI / 2, 1e-9)
    assert.closeTo(run.x, 4, 1e-9)
    assert.closeTo(run.y, 10, 1e-9)
  })

  test('el punto interior de una L cae dentro de la L', ({ assert }) => {
    // L: el centroide (≈ 3.9, 3.9) queda en el hueco de la esquina.
    const ring = Float64Array.from([0, 0, 10, 0, 10, 2, 2, 2, 2, 10, 0, 10, 0, 0])
    const p = interiorPoint([ring])
    const insideBottom = p.x >= 0 && p.x <= 10 && p.y >= 0 && p.y <= 2
    const insideLeft = p.x >= 0 && p.x <= 2 && p.y >= 0 && p.y <= 10
    assert.isTrue(insideBottom || insideLeft, `punto fuera de la L: ${p.x}, ${p.y}`)
  })
})

test.group('Map labels · chunks', () => {
  test('una calle con nombre partida en dos vías da una sola etiqueta con su trazado', ({
    assert,
  }) => {
    const labels = labelsOf([
      {
        kind: 'line',
        id: 'w2',
        tags: { highway: 'residential', name: 'Calle Mayor' },
        coords: line(C, [
          [-10, 20.5],
          [30, 20.5],
        ]),
      },
      {
        kind: 'line',
        id: 'w1',
        tags: { highway: 'residential', name: 'Calle Mayor' },
        coords: line(C, [
          [30, 20.5],
          [80, 20.5],
        ]),
      },
      {
        kind: 'line',
        id: 'w3',
        tags: { highway: 'residential' },
        coords: line(C, [
          [5, 5],
          [5, 50],
        ]),
      },
    ])
    const streets = labels.filter((l) => l.kind === 'street')
    assert.lengthOf(streets, 1)
    const [street] = streets
    assert.equal(street.name, 'Calle Mayor')
    assert.equal(street.id, 'w1')
    assert.equal(street.rank, 5)
    assert.lengthOf(street.paths!, 2)
    // Tramo horizontal: ángulo ~0 y ancla sobre la calle.
    assert.closeTo(street.angle!, 0, 0.01)
    assert.closeTo(street.at[1], 20.5, 0.15)
    assert.isAtLeast(street.len!, 30)
  })

  test('los túneles no tienen etiqueta', ({ assert }) => {
    const labels = labelsOf([
      {
        kind: 'line',
        id: 'w1',
        tags: { highway: 'primary', name: 'Túnel', tunnel: 'yes' },
        coords: line(C, [
          [0, 10],
          [60, 10],
        ]),
      },
    ])
    assert.lengthOf(labels, 0)
  })

  test('un parque se etiqueta una sola vez, en el chunk que contiene su centro', ({ assert }) => {
    const park: Feature = {
      kind: 'area',
      id: 'w9',
      tags: { leisure: 'park', name: 'Parque Grande' },
      rings: [rect(C, 10, 10, 100, 40)], // centro en x=55: dentro de este chunk
    }
    const here = labelsOf([park])
    const next = labelsOf([park], { ...C, x: C.x + 1 })
    assert.lengthOf(here, 1)
    assert.equal(here[0].kind, 'park')
    assert.closeTo(here[0].at[0], 55, 0.2)
    assert.equal(here[0].rank, 6) // área grande: +2
    assert.lengthOf(next, 0)
  })

  test('no repite el nombre de un edificio que ya es POI', ({ assert }) => {
    const labels = labelsOf([
      {
        kind: 'area',
        id: 'w1',
        tags: { building: 'yes', tourism: 'museum', name: 'Museo' },
        rings: [rect(C, 20, 20, 30, 30)],
      },
      {
        kind: 'area',
        id: 'w2',
        tags: { building: 'yes', name: 'Casa de las Flores' },
        rings: [rect(C, 40, 40, 44, 44)],
      },
      {
        kind: 'point',
        id: 'n1',
        tags: { tourism: 'museum', name: 'Museo' },
        coord: localToLonLat(C, 25, 25),
      },
    ])
    assert.deepEqual(
      labels.map((l) => [l.kind, l.name]),
      [['building', 'Casa de las Flores']]
    )
  })

  test('números de portal de nodos y edificios, sin duplicar', ({ assert }) => {
    const labels = labelsOf([
      {
        kind: 'area',
        id: 'w1',
        tags: { 'building': 'yes', 'addr:housenumber': '12' },
        rings: [rect(C, 10, 10, 14, 14)],
      },
      {
        kind: 'point',
        id: 'n1',
        tags: { 'addr:housenumber': '12' },
        coord: localToLonLat(C, 12, 14),
      },
      {
        kind: 'point',
        id: 'n2',
        tags: { 'addr:housenumber': '14' },
        coord: localToLonLat(C, 20, 14),
      },
    ])
    const numbers = labels.filter((l) => l.kind === 'number').map((l) => l.name)
    assert.deepEqual(numbers.sort(), ['12', '14'])
  })

  test('los barrios se etiquetan en su nodo, con rango alto', ({ assert }) => {
    const labels = labelsOf([
      {
        kind: 'point',
        id: 'n1',
        tags: { place: 'neighbourhood', name: 'Chapinero Alto' },
        coord: localToLonLat(C, 20.5, 30.5),
      },
    ])
    assert.lengthOf(labels, 1)
    assert.equal(labels[0].kind, 'district')
    assert.equal(labels[0].name, 'Chapinero Alto')
    assert.isAtLeast(labels[0].rank, 8)
  })

  test('el chunk sabe en qué barrio está aunque el punto caiga fuera', ({ assert }) => {
    const place = (id: string, kind: string, name: string, x: number, y: number): Feature => ({
      kind: 'point',
      id,
      tags: { place: kind, name },
      coord: localToLonLat(C, x, y),
    })
    const districtOf = (features: Feature[]) => {
      const r = new SourceRasterizer(
        featureSet(features),
        { cellZoom: CELL_ZOOM, chunkZoom: CHUNK_ZOOM },
        tileCenterLatitude(CHUNK_ZOOM, C.y)
      )
      return r.rasterizeChunk(C.z, C.x, C.y).district
    }

    // El más cercano al centro del chunk (32, 32), aunque esté en otro chunk.
    assert.equal(
      districtOf([
        place('n1', 'neighbourhood', 'Cerca', 150, 32),
        place('n2', 'quarter', 'Lejos', -300, 32),
      ]),
      'Cerca'
    )
    // Un barrio al alcance gana a la localidad (suburb) aunque esta esté más cerca.
    assert.equal(
      districtOf([
        place('n1', 'suburb', 'Chapinero', 40, 40),
        place('n2', 'neighbourhood', 'Quinta Camacho', 200, 32),
      ]),
      'Quinta Camacho'
    )
    // Sin barrio, la localidad.
    assert.equal(districtOf([place('n1', 'suburb', 'Chapinero', 40, 40)]), 'Chapinero')
    // Demasiado lejos (> 1,5 km) o sin datos: null.
    assert.isNull(districtOf([place('n1', 'neighbourhood', 'Lejísimos', 2000, 32)]))
    assert.isNull(districtOf([]))
  })
})
