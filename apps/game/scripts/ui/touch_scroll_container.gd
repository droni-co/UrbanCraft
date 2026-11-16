class_name TouchScrollContainer
extends ScrollContainer
## ScrollContainer que se desplaza arrastrando con el dedo desde cualquier
## parte de su contenido, con inercia al soltar.
##
## El ScrollContainer del motor solo recibe el arrastre si el dedo cae en un
## hueco: los botones, paneles y textos (mouse_filter STOP) se quedan con el
## toque, así que una lista de botones no se podía mover en el teléfono. Aquí
## los toques se leen en `_input`, antes de que lleguen a los controles: un
## toque corto sigue siendo un clic normal y, si el dedo se arrastra, la lista
## se mueve y el botón que estaba debajo no se dispara al soltar.
##
## Con ratón no cambia nada (rueda y barra de desplazamiento).

## Lo que debe moverse el dedo (px de la resolución base) para que cuente como
## arrastre y no como toque.
const DRAG_THRESHOLD := 6.0
## Qué tan rápido se frena la inercia, y velocidad (px/s) a la que se detiene.
const FRICTION := 5.0
const MIN_SPEED := 8.0
## Si el dedo llevaba quieto este tiempo (ms) al soltar, no hay inercia.
const FLICK_MAX_PAUSE_MS := 90

## Índice del toque -> id del contenedor que lo atiende (uno solo por toque,
## aunque haya varios bajo el dedo: gana el que está más arriba en pantalla).
static var _owners := {}

var _touch := -1
var _press_position := Vector2.ZERO
var _travel := Vector2.ZERO
var _dragging := false
var _velocity := Vector2.ZERO
var _last_drag_ms := 0
## Fracción de píxel pendiente (el desplazamiento del contenedor es entero).
var _remainder := Vector2.ZERO


func _ready() -> void:
	# El arrastre táctil del motor queda apagado: lo hace este script.
	scroll_deadzone = 1 << 20
	set_process(false)


func _exit_tree() -> void:
	_release_touch()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event)
		elif event.index == _touch:
			_on_release()
	elif event is InputEventScreenDrag and event.index == _touch:
		_on_drag(event)


func _on_press(event: InputEventScreenTouch) -> void:
	if _touch != -1 or _owners.has(event.index):
		return
	if not is_visible_in_tree() or not get_global_rect().has_point(event.position):
		return
	_owners[event.index] = get_instance_id()
	_touch = event.index
	_press_position = event.position
	_travel = Vector2.ZERO
	_remainder = Vector2.ZERO
	_velocity = Vector2.ZERO
	_dragging = false
	set_process(false)  # tocar la lista detiene la inercia


func _on_drag(event: InputEventScreenDrag) -> void:
	var now := Time.get_ticks_msec()
	if not _dragging:
		_travel += event.relative
		var moved := absf(_travel.y) if vertical_scroll_mode != SCROLL_MODE_DISABLED else 0.0
		if horizontal_scroll_mode != SCROLL_MODE_DISABLED:
			moved = maxf(moved, absf(_travel.x))
		if moved < DRAG_THRESHOLD:
			return
		_dragging = true
		_cancel_presses()
	else:
		var seconds := maxf((now - _last_drag_ms) / 1000.0, 0.004)
		_velocity = _velocity.lerp(event.relative / seconds, 0.6)
	_last_drag_ms = now
	_scroll_by(-event.relative)
	get_viewport().set_input_as_handled()


func _on_release() -> void:
	var flick := _dragging and Time.get_ticks_msec() - _last_drag_ms <= FLICK_MAX_PAUSE_MS
	_release_touch()
	if flick and _velocity.length() > MIN_SPEED:
		set_process(true)
	else:
		_velocity = Vector2.ZERO


func _release_touch() -> void:
	if _touch != -1 and _owners.get(_touch) == get_instance_id():
		_owners.erase(_touch)
	_touch = -1
	_dragging = false


## Inercia: la lista sigue un poco después de soltar.
func _process(delta: float) -> void:
	if not _scroll_by(-_velocity * delta):
		_velocity = Vector2.ZERO  # llegó al tope
	_velocity = _velocity.lerp(Vector2.ZERO, 1.0 - exp(-FRICTION * delta))
	if _velocity.length() < MIN_SPEED:
		_velocity = Vector2.ZERO
		set_process(false)


## Desplaza el contenido; false si ya no se movió (tope de la lista).
func _scroll_by(amount: Vector2) -> bool:
	_remainder += amount
	var step := Vector2i(_remainder)  # trunca hacia cero
	_remainder -= Vector2(step)
	if step == Vector2i.ZERO:
		return true
	var before := Vector2i(scroll_horizontal, scroll_vertical)
	if horizontal_scroll_mode != SCROLL_MODE_DISABLED:
		scroll_horizontal += step.x
	if vertical_scroll_mode != SCROLL_MODE_DISABLED:
		scroll_vertical += step.y
	return Vector2i(scroll_horizontal, scroll_vertical) != before


## El toque empezó sobre un botón, pero resultó ser un arrastre: se cancela su
## pulsación para que no se dispare al levantar el dedo. Desactivarlo un
## instante es la forma que da el motor de olvidar una pulsación a medias.
func _cancel_presses() -> void:
	for node in find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button.disabled or not button.is_visible_in_tree():
			continue
		if button.get_global_rect().has_point(_press_position):
			button.disabled = true
			button.disabled = false
