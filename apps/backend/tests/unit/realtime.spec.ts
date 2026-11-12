import { test } from '@japa/runner'
import { PresenceWorld, snap } from '#realtime/presence_world'
import { cleanChatText, parseClientMessage } from '#realtime/protocol'

test.group('Multijugador: protocolo', () => {
  test('valida los mensajes del cliente', ({ assert }) => {
    assert.deepEqual(parseClientMessage('{"t":"state","x":10.5,"y":3,"d":7,"m":2}'), {
      t: 'state',
      x: 10.5,
      y: 3,
      d: 7,
      m: 2,
      spawn: false,
    })
    assert.isNull(parseClientMessage('{"t":"state","x":-1,"y":3,"d":0,"m":0}'))
    assert.isNull(parseClientMessage('{"t":"state","x":1,"y":3,"d":8,"m":0}'))
    assert.isNull(parseClientMessage('{"t":"state","x":"1","y":3,"d":0,"m":0}'))
    assert.isNull(parseClientMessage('{"t":"act","k":"hack"}'))
    assert.isNull(parseClientMessage('no json'))
    assert.isNull(parseClientMessage('[1,2]'))
    assert.deepEqual(parseClientMessage('{"t":"vis","v":false}'), { t: 'vis', v: false })
    assert.deepEqual(parseClientMessage('{"t":"say","m":" hola "}'), { t: 'say', m: 'hola' })
    assert.isNull(parseClientMessage('{"t":"say","m":42}'))
  })

  test('limpia los mensajes de chat', ({ assert }) => {
    assert.equal(cleanChatText('hola\u0000\tmundo\r\n'), 'hola mundo')
    assert.equal(cleanChatText('abc\u202Edef'), 'abc def') // sin voltear el texto
    assert.equal(cleanChatText('¡Buenas! 👋🏽 👨‍👩‍👧'), '¡Buenas! 👋🏽 👨‍👩‍👧') // emojis con ZWJ intactos
    assert.equal(cleanChatText('😀'.repeat(200)), '😀'.repeat(200)) // cuenta caracteres, no bytes
    assert.isNull(cleanChatText('😀'.repeat(201)))
    assert.isNull(cleanChatText(' \n '))
    assert.isNull(cleanChatText(null))
  })
})

test.group('Multijugador: índice espacial', () => {
  test('encuentra a los cercanos, sin el propio, y sigue los movimientos', ({ assert }) => {
    const world = new PresenceWorld(128, 24)
    for (const id of [1, 2, 3])
      world.join({ id, nickname: `p${id}`, level: 1, skin: null, visible: true })
    world.move(1, 1000, 1000)
    world.move(2, 1030, 1000) // otra cubeta (borde en 1024)
    world.move(3, 5000, 5000)

    assert.deepEqual(
      world.within(1000, 1000, 40, 1).map((p) => p.id),
      [2]
    )
    assert.lengthOf(world.within(1000, 1000, 20, 1), 0)

    world.move(3, 1010, 990)
    assert.sameMembers(
      world.within(1000, 1000, 40, 1).map((p) => p.id),
      [2, 3]
    )

    world.get(2)!.visible = false
    assert.deepEqual(
      world.within(1000, 1000, 40, 1).map((p) => p.id),
      [3]
    )

    world.leave(3)
    assert.lengthOf(world.within(1000, 1000, 40, 1), 0)
    assert.equal(world.size, 2)
  })

  test('los que aún no enviaron posición no aparecen', ({ assert }) => {
    const world = new PresenceWorld(128, 24)
    world.join({ id: 1, nickname: 'a', level: 1, skin: null, visible: true })
    assert.lengthOf(world.within(0, 0, 10), 0)
  })

  test('redondeo del radar', ({ assert }) => {
    assert.equal(snap(1234.4, 10), 1230)
    assert.equal(snap(1236, 10), 1240)
    assert.equal(snap(12.6, 0.5), 13)
  })
})
