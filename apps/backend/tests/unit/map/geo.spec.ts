import { test } from '@japa/runner'
import {
  childTiles,
  expandBBox,
  latToWorld,
  lonLatToTile,
  lonToWorld,
  metersPerUnit,
  parentTile,
  tileBounds,
  tilesAround,
  worldToLat,
  worldToLon,
} from '#map/geo'

test.group('Map geo', () => {
  test('lon/lat <-> world es reversible', ({ assert }) => {
    for (const [lon, lat] of [
      [-3.6887, 40.42],
      [-74.0721, 4.711],
      [151.2093, -33.8688],
      [0, 0],
    ]) {
      assert.approximately(worldToLon(lonToWorld(lon, 24), 24), lon, 1e-9)
      assert.approximately(worldToLat(latToWorld(lat, 24), 24), lat, 1e-9)
    }
  })

  test('tiles conocidos (slippy map)', ({ assert }) => {
    assert.deepEqual(lonLatToTile(0, 0, 1), [1, 1])
    assert.deepEqual(lonLatToTile(-3.6887, 40.42, 15), [16048, 12355])
  })

  test('jerarquía padre/hijos', ({ assert }) => {
    assert.deepEqual(parentTile(18, 128385, 98843, 15), [16048, 12355])
    const children = childTiles(15, 16048, 12355, 18)
    assert.lengthOf(children, 64)
    assert.deepInclude(children, [128385, 98843])
    for (const [x, y] of children) assert.deepEqual(parentTile(18, x, y, 15), [16048, 12355])
  })

  test('bounds de un tile contienen su punto', ({ assert }) => {
    const b = tileBounds(15, 16048, 12355)
    assert.isTrue(b.west <= -3.6887 && -3.6887 < b.east)
    assert.isTrue(b.south <= 40.42 && 40.42 < b.north)
  })

  test('metros por celda a cellZoom 24', ({ assert }) => {
    assert.approximately(metersPerUnit(0, 24), 2.389, 0.001)
    assert.approximately(metersPerUnit(60, 24), 1.194, 0.001)
  })

  test('expandBBox y tilesAround', ({ assert }) => {
    const b = expandBBox({ west: 0, east: 0, south: 0, north: 0 }, 1113.2)
    assert.approximately(b.north, 0.01, 1e-6)
    assert.approximately(b.east, 0.01, 1e-6)
    const tiles = tilesAround(-3.6887, 40.42, 1000, 15)
    assert.isAtLeast(tiles.length, 4)
    assert.deepInclude(tiles, [16048, 12355])
  })
})
