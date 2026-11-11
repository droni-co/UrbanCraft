class_name RemotePlayer
extends Node2D
## Otro jugador conectado: mismo sprite que el jugador, su apodo encima y
## burbujas con sus acciones. No colisiona (se puede atravesar).
##
## Interpolación: guarda los últimos estados que manda el servidor y se dibuja
## INTERP_DELAY por detrás, entre dos de ellos, para moverse suave aunque los
## paquetes lleguen a saltos. Si se queda sin datos, mantiene la última posición.

const INTERP_DELAY := 0.15
## Saltos mayores (en píxeles) no se interpolan: teletransporte o reaparición.
const TELEPORT_DISTANCE := 256.0
const NAME_FONT_SIZE := 8
const BUBBLE_TEXT := {"interact": "!", "wave": "¡Hola!"}

var player_id := 0
var skin := ""

## [{ t, pos: Vector2, d, m }] ordenados por t
var _samples: Array[Dictionary] = []
var _sprite: AnimatedSprite2D
var _name_label: Label
var _bubble: Label
var _bubble_tween: Tween
var _dir := 2
var _move := 0


func _ready() -> void:
	_set_skin(null)
	_name_label = _make_label(NAME_FONT_SIZE, Color(1, 1, 1, 0.95))
	_name_label.position.y = -Player.FEET.y - 12
	add_child(_name_label)
	_bubble = _make_label(NAME_FONT_SIZE + 2, Color("ffd75e"))
	_bubble.position.y = -Player.FEET.y - 24
	_bubble.modulate.a = 0.0
	add_child(_bubble)


func set_info(nickname: String, level: int, skin_id: Variant = null) -> void:
	_name_label.text = "%s · Nv %d" % [nickname, level]
	_center(_name_label)
	_set_skin(skin_id)


func _set_skin(id: Variant) -> void:
	var resolved := CharacterSkins.resolve(id)
	if resolved == skin and _sprite:
		return
	skin = resolved
	if _sprite == null:
		_sprite = CharacterSkins.make_sprite(skin)
		if _sprite:
			add_child(_sprite)
			move_child(_sprite, 0)  # debajo del nombre y la burbuja
			_sprite.play("idle_s")
	elif not skin.is_empty():
		var anim := _sprite.animation
		_sprite.sprite_frames = CharacterSkins.frames(skin)
		_sprite.play(anim)


## Nuevo estado del servidor (posición ya convertida a coordenadas del mundo).
func push_state(time: float, pos: Vector2, dir: int, move: int) -> void:
	if not _samples.is_empty() and _samples[-1].pos.distance_to(pos) > TELEPORT_DISTANCE:
		_samples.clear()
	if _samples.is_empty():
		position = pos
	_samples.append({"t": time, "pos": pos, "d": dir, "m": move})
	while _samples.size() > 8:
		_samples.pop_front()


func show_action(kind: String) -> void:
	_bubble.text = BUBBLE_TEXT.get(kind, "…")
	_center(_bubble)
	if _bubble_tween:
		_bubble_tween.kill()
	_bubble.modulate.a = 1.0
	_bubble.position.y = -Player.FEET.y - 24
	_bubble_tween = create_tween().set_parallel()
	_bubble_tween.tween_property(_bubble, "position:y", _bubble.position.y - 6, 1.4)
	_bubble_tween.tween_property(_bubble, "modulate:a", 0.0, 0.5).set_delay(0.9)
	if kind == "wave" and _sprite:
		var hop := create_tween()
		hop.tween_property(_sprite, "position:y", -4.0, 0.12)
		hop.tween_property(_sprite, "position:y", 0.0, 0.12)


func _process(_delta: float) -> void:
	if _samples.is_empty():
		return
	var render_time := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	var a: Dictionary = _samples[0]
	var b: Dictionary = _samples[-1]
	for i in range(_samples.size() - 1):
		if _samples[i + 1].t >= render_time:
			a = _samples[i]
			b = _samples[i + 1]
			break
	var span: float = b.t - a.t
	var w := clampf((render_time - a.t) / span, 0.0, 1.0) if span > 0.0 else 1.0
	position = a.pos.lerp(b.pos, w)
	var current: Dictionary = b if w >= 0.5 else a
	# Sin datos nuevos hace rato (se perdieron paquetes): mostrarlo quieto.
	var stale := render_time - float(_samples[-1].t) > 0.5
	_dir = int(current.d)
	_move = 0 if stale else int(current.m)
	if _sprite:
		var anim := ("walk_" if _move > 0 else "idle_") + Player.DIRECTIONS[_dir]
		if _sprite.animation != anim:
			_sprite.play(anim)
		_sprite.speed_scale = 1.6 if _move == 2 else 1.0
	queue_redraw()


func _draw() -> void:
	# Sombra (como el jugador).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	if _sprite == null:
		draw_rect(Rect2(-5, -17, 10, 12), Color("4a8fe8"))
		draw_circle(Vector2(0, -22), 5.5, Color("f1c27d"))


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _center(label: Label) -> void:
	label.reset_size()
	label.position.x = -label.size.x / 2.0
