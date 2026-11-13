import { test } from '@japa/runner'

test.group('Hora del servidor', () => {
  test('GET /api/v1/time devuelve la hora actual sin caché', async ({ client, assert }) => {
    const before = Date.now()
    const response = await client.get('/api/v1/time')
    response.assertStatus(200)
    const now = (response.body() as { now: number }).now
    assert.isAtLeast(now, before)
    assert.isAtMost(now, Date.now())
    assert.equal(response.header('cache-control'), 'no-store')
  })
})
