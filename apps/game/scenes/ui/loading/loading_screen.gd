class_name LoadingScreen
extends Control
## Pantalla de carga del mundo: barra de progreso y qué se está haciendo.
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
const CARD_WIDTH := 260.0
const BAR_SIZE := Vector2(232, 8)
const BAR_COLOR := Color("5fb3ff")
const READY_COLOR := Color("7ee787")

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
	get_tree().create_timer(0.45, true, false, true).timeout.connect(_close)


func _close() -> void:
	if not _open:
		return
	_open = false
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void:
		visible = false
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
	_title.text = "Cargando el mapa"
	_detail.text = ""


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


# --- Interfaz -------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.09, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var card := PanelContainer.new()
	card.custom_minimum_size.x = CARD_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.92)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	style.border_color = Color(1, 1, 1, 0.08)
	style.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	card.add_child(column)

	_title = _label("Cargando el mapa", 12, Color.WHITE)
	column.add_child(_title)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = BAR_SIZE
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.1)
	back.set_corner_radius_all(4)
	_fill = StyleBoxFlat.new()
	_fill.bg_color = BAR_COLOR
	_fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", back)
	_bar.add_theme_stylebox_override("fill", _fill)
	column.add_child(_bar)

	_status = _label("", 9, Color(1, 1, 1, 0.85))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_detail = _label("", 8, Color(1, 1, 1, 0.55))
	column.add_child(_detail)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.custom_minimum_size.x = CARD_WIDTH - 20
	return label
