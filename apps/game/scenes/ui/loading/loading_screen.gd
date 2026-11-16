class_name LoadingScreen
extends Control
## Pantalla de carga del mundo: ilustración a pantalla completa (rotan las de
## assets/art/ui/screens, con un paneo lento), consejos, barra de progreso y
## qué se está haciendo.
## Cuando la zona es nueva (el servidor la genera: 30-60 s) estima cuánto falta
## con lo que responde el servidor.
##
## La usa el HUD (Hud.set_loading) y el mundo (server_progress):
##   set_status(texto, progreso) -> etapas del cliente (conectar, ubicar…)
##   server_progress(p)          -> respuesta 202 del servidor (ChunkProgress en
##                                  apps/backend/app/services/map_chunk_service.ts)
##   finish()                    -> el mapa está listo (se cierra sola)

signal closed

## Tramo de la barra que corresponde a la generación en el servidor.
const SERVER_FROM := 0.15
const SERVER_TO := 0.95
const CARD_WIDTH := 300.0
const BAR_SIZE := Vector2(280, 10)
const BAR_COLOR := MenuTheme.TERRACOTTA
const READY_COLOR := Color("7ec96a")
## Segundos que se ve cada ilustración y cada consejo.
const SLIDE_SECONDS := 7.0
const TIP_SECONDS := 6.0
const TIPS: Array[String] = [
	"El mapa es tu ciudad real: calles, parques y edificios salen de OpenStreetMap.",
	"Mantén Shift para correr (en pantalla táctil, el botón B).",
	"Pulsa G para saludar a los jugadores que tengas cerca.",
	"Pulsa Enter para abrir el chat con los jugadores cercanos y tus amigos.",
	"Mantén V para hablar por voz con tus amigos.",
	"El día y la noche siguen la hora real de tu ciudad.",
	"Desde Menú → Teletransporte puedes visitar cualquier lugar del mundo.",
	"Cambia de personaje en Menú → Personaje: los demás verán tu elección.",
	"Agrega amigos desde Menú → Amigos para chatear y hablar con ellos.",
	"Cuida tu hambre: la barra baja mientras exploras.",
]

var _open := false
var _target := 0.0
var _shown := 0.0
var _server := {}
var _server_at := 0.0
var _server_started := -1.0

var _title: Label
var _status: Label
var _detail: Label
var _bar: ProgressBar
var _fill: StyleBoxFlat
var _slides: Array[TextureRect] = []
var _slide := 0
var _slide_order: Array[String] = []
var _tip: Label
var _tip_index := 0
var _timers: Array[Timer] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # que los clics no lleguen al mundo
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func is_open() -> bool:
	return _open


## Etapa del cliente (conectando, ubicando…). progress < 0 = no cambia la barra.
func set_status(text: String, progress := -1.0) -> void:
	_show()
	_status.text = text
	if progress >= 0.0:
		_target = maxf(_target, progress)


## Progreso de la zona que está generando el servidor.
func server_progress(p: Dictionary) -> void:
	_show()
	if p.is_empty():  # 429: hay muchas zonas nuevas pedidas
		_status.text = "El servidor está ocupado generando otras zonas…"
		return
	if _server_started < 0.0:
		_server_started = _now()
	_server = p
	_server_at = _now()
	_title.text = "Preparando tu zona por primera vez"
	match str(p.get("stage", "")):
		"queued":
			var ahead := int(p.get("ahead", 0))
			_status.text = "En cola: %d %s antes que la tuya" % [ahead, "zona" if ahead == 1 else "zonas"] \
				if ahead > 0 else "Pidiendo los datos de tu zona…"
		"download":
			_status.text = "Descargando calles, edificios y lugares de OpenStreetMap…"
		"build":
			_status.text = "Armando el mapa…"
	_refresh_estimate()


## El mapa está listo.
func finish() -> void:
	if not _open:
		return
	_target = 1.0
	_server = {}
	_title.text = "¡Tu zona está lista!"
	_status.text = ""
	_detail.text = ""
	_fill.bg_color = READY_COLOR
	_fill.border_color = READY_COLOR.darkened(0.4)
	get_tree().create_timer(0.45, true, false, true).timeout.connect(_close)


func _close() -> void:
	if not _open:
		return
	_open = false
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void:
		visible = false
		for t in _timers:
			t.stop()
		closed.emit())


func _show() -> void:
	if _open:
		return
	_open = true
	visible = true
	modulate.a = 1.0
	# Por si se reabre después de terminar: empezar de cero.
	_target = 0.0
	_shown = 0.0
	_server = {}
	_server_started = -1.0
	_fill.bg_color = BAR_COLOR
	_fill.border_color = BAR_COLOR.darkened(0.45)
	_title.text = "Cargando el mapa"
	_detail.text = ""
	_start_slides()


# --- Progreso -------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _open:
		return
	if not _server.is_empty():
		_refresh_estimate()
	# La barra nunca retrocede y se acerca suave al objetivo.
	_shown = minf(_target, _shown + maxf(0.002, (_target - _shown) * delta * 4.0))
	_bar.value = _shown


## Estimación con lo que dijo el servidor: zonas delante, cuánto lleva la
## descarga y cuánto suele tardar una. La barra avanza aunque no lleguen
## respuestas (se piden cada 2-5 s) y nunca llega al final antes de tiempo.
func _refresh_estimate() -> void:
	var p := _server
	var expected := maxf(float(p.get("expected", 35)), 1.0)
	var since := _now() - _server_at
	var remaining := float(p.get("ahead", 0)) * expected
	if str(p.get("stage", "")) == "queued":
		remaining += expected
	else:
		remaining += expected - (float(p.get("elapsed", 0)) + since)
	remaining = maxf(remaining, expected * 0.08)
	var done := _now() - _server_started
	var fraction := done / (done + remaining)
	_target = maxf(_target, lerpf(SERVER_FROM, SERVER_TO, fraction))

	var attempts := int(p.get("attempts", 0))
	if attempts > 0:
		_detail.text = "OpenStreetMap está ocupado: reintento %d…" % attempts
	elif remaining > expected * 0.1:
		_detail.text = "Faltan unos %d s" % (ceili(remaining / 5.0) * 5)
	else:
		_detail.text = "Ya casi…"


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- Ilustraciones y consejos ---------------------------------------------------

func _start_slides() -> void:
	_slide_order = UiArt.LOADING_SCREENS.duplicate()
	_slide_order.shuffle()
	_slide = 0
	_show_slide(_slides[0], _slide_order[0], true)
	_slides[1].modulate.a = 0.0
	_tip_index = randi() % TIPS.size()
	_tip.text = TIPS[_tip_index]
	for t in _timers:
		t.start()


func _next_slide() -> void:
	_slide += 1
	var front := _slides[_slide % 2]
	var back := _slides[(_slide + 1) % 2]
	_show_slide(front, _slide_order[_slide % _slide_order.size()], false)
	move_child(front, back.get_index())  # la nueva queda encima y aparece
	var t := create_tween()
	t.tween_property(front, "modulate:a", 1.0, 1.2)


## Una ilustración con zoom lento hacia adentro (o hacia afuera, alternando).
func _show_slide(rect: TextureRect, screen_name: String, instant: bool) -> void:
	rect.texture = UiArt.screen(screen_name)
	rect.pivot_offset = rect.size / 2.0
	rect.modulate.a = 1.0 if instant else 0.0
	var zoom_in := _slide % 2 == 0
	rect.scale = Vector2.ONE * (1.02 if zoom_in else 1.12)
	var t := create_tween()
	t.tween_property(rect, "scale", Vector2.ONE * (1.12 if zoom_in else 1.02), SLIDE_SECONDS + 1.5)


func _next_tip() -> void:
	_tip_index = (_tip_index + 1) % TIPS.size()
	var t := create_tween()
	t.tween_property(_tip, "modulate:a", 0.0, 0.3)
	t.tween_callback(func() -> void: _tip.text = TIPS[_tip_index])
	t.tween_property(_tip, "modulate:a", 1.0, 0.3)


# --- Interfaz -------------------------------------------------------------------

func _build() -> void:
	UiArt.smooth(self)
	theme = MenuTheme.build()
	var back := ColorRect.new()
	back.color = Color("0d1626")
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for i in 2:
		var art := TextureRect.new()
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.resized.connect(func() -> void: art.pivot_offset = art.size / 2.0)
		_slides.append(art)

	# Oscurece abajo para leer el progreso.
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.04, 0.07, 0.13, 0.0), Color(0.04, 0.07, 0.13, 0.0), Color(0.04, 0.07, 0.13, 0.92)])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var shade_tex := GradientTexture2D.new()
	shade_tex.gradient = g
	shade_tex.fill_to = Vector2(0, 1)
	shade_tex.width = 4
	shade_tex.height = 256
	var shade := TextureRect.new()
	shade.texture = shade_tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var logo := TextureRect.new()
	logo.texture = UiArt.LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	logo.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	logo.position = Vector2(12, 8)
	logo.size = Vector2(130, 130.0 * UiArt.LOGO.get_height() / UiArt.LOGO.get_width())

	# Abajo al centro: título, barra, estado y un consejo.
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.offset_left = -CARD_WIDTH / 2.0
	column.offset_right = CARD_WIDTH / 2.0
	column.offset_bottom = -14.0

	var tip_box := PanelContainer.new()
	tip_box.add_theme_stylebox_override("panel", UiArt.chip(8, 0.78))
	tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tip_box)
	var tip_row := HBoxContainer.new()
	tip_row.add_theme_constant_override("separation", 6)
	tip_box.add_child(tip_row)
	var bulb := UiArt.icon_rect("xp", 14)
	bulb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tip_row.add_child(bulb)
	_tip = Label.new()
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip.add_theme_font_size_override("font_size", 9)
	_tip.add_theme_color_override("font_color", MenuTheme.TEXT)
	tip_row.add_child(_tip)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 4
	column.add_child(spacer)

	_title = _label("Cargando el mapa", 14, Color.WHITE)
	_title.add_theme_font_override("font", UiArt.FONT_DISPLAY)
	column.add_child(_title)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = BAR_SIZE
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back_bar := StyleBoxFlat.new()
	back_bar.bg_color = Color(0.02, 0.04, 0.09, 0.75)
	back_bar.set_corner_radius_all(5)
	back_bar.border_color = Color(MenuTheme.GOLD, 0.7)
	back_bar.set_border_width_all(1)
	back_bar.anti_aliasing = true
	_fill = StyleBoxFlat.new()
	_fill.bg_color = BAR_COLOR
	_fill.set_corner_radius_all(5)
	# Labio más oscuro abajo, como en los botones.
	_fill.border_color = BAR_COLOR.darkened(0.45)
	_fill.border_width_bottom = 2
	_fill.anti_aliasing = true
	_bar.add_theme_stylebox_override("background", back_bar)
	_bar.add_theme_stylebox_override("fill", _fill)
	column.add_child(_bar)

	_status = _label("", 10, Color(1, 1, 1, 0.92))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_detail = _label("", 9, Color(1, 1, 1, 0.6))
	column.add_child(_detail)

	var slide_timer := Timer.new()
	slide_timer.wait_time = SLIDE_SECONDS
	slide_timer.timeout.connect(_next_slide)
	add_child(slide_timer)
	var tip_timer := Timer.new()
	tip_timer.wait_time = TIP_SECONDS
	tip_timer.timeout.connect(_next_tip)
	add_child(tip_timer)
	_timers = [slide_timer, tip_timer]


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("outline_size", 3)
	label.custom_minimum_size.x = CARD_WIDTH
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
