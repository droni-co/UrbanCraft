class_name StatsPanel
extends PanelContainer
## Panel compacto de stats bajo el botón de menú (hambre, nivel, dinero…).
##
## Se arma a partir del catálogo que manda el servidor (PlayerStats): los stats
## con hud = true aparecen solos, en su orden, con su icono
## (assets/art/ui/icons/<icon>.png) y según su tipo:
##   meter   → barra       (hambre)
##   level   → "Nv 3" + barra fina de progreso (experiencia)
##   counter → número       (dinero)
## Al pasar el ratón (o mantener pulsado) muestra el detalle de cada uno.

const ICON_DIR := "res://assets/art/ui/icons/"
const FALLBACK_ICON := "stat"
const ICON_SIZE := Vector2(12, 12)
const FONT_SIZE := 8
const METER_SIZE := Vector2(40, 5)
const LEVEL_BAR_SIZE := Vector2(26, 3)
const ROW_HEIGHT := 12.0
## Por debajo de esta fracción una barra se pone roja y parpadea.
const LOW_FRACTION := 0.2
const LOW_COLOR := Color("ff6b5e")
const TEXT_COLOR := Color(1, 1, 1, 0.92)

## key -> { def, row, bar?, label?, shown_value }
var _rows := {}
var _keys: PackedStringArray = []
var _icons := {}
var _low_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # un toque aquí no mueve al jugador
	add_theme_stylebox_override("panel", _panel_style())
	var column := VBoxContainer.new()
	column.name = "Rows"
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	PlayerStats.updated.connect(_on_updated)
	PlayerStats.stat_changed.connect(_on_stat_changed)
	GameSettings.stats_settings_changed.connect(_refresh_visibility)
	_on_updated(PlayerStats.stats)


func _on_updated(stats: Array) -> void:
	var hud_stats := stats.filter(func(s: Dictionary) -> bool: return s.get("hud", false))
	var keys := PackedStringArray(hud_stats.map(func(s: Dictionary) -> String: return s.key))
	if keys != _keys:
		_rebuild(hud_stats)
		_keys = keys
	for s: Dictionary in hud_stats:
		_update_row(s, false)
	tooltip_text = "\n".join(hud_stats.map(func(s: Dictionary) -> String: return PlayerStats.describe(s)))
	_refresh_visibility()


func _refresh_visibility() -> void:
	visible = GameSettings.stats_hud_visible and not _rows.is_empty()


# --- Filas -----------------------------------------------------------------------

func _rebuild(stats: Array) -> void:
	var column: VBoxContainer = $Rows
	for child in column.get_children():
		child.queue_free()
	_rows.clear()
	for s: Dictionary in stats:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		row.custom_minimum_size.y = ROW_HEIGHT
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(row)

		var icon := TextureRect.new()
		icon.texture = _icon(str(s.get("icon", FALLBACK_ICON)))
		icon.custom_minimum_size = ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

		var entry := {"def": s, "row": row, "shown_value": float(s.value)}
		var color := Color(str(s.get("color", "#ffffff")))
		match s.get("kind"):
			"meter":
				entry.bar = _bar(METER_SIZE, color)
				row.add_child(entry.bar)
			"level":
				entry.label = _label(color)
				row.add_child(entry.label)
				entry.bar = _bar(LEVEL_BAR_SIZE, color)
				row.add_child(entry.bar)
			_:
				entry.label = _label(color)
				row.add_child(entry.label)
		_rows[s.key] = entry


func _update_row(s: Dictionary, animate: bool) -> void:
	var entry: Dictionary = _rows.get(s.key, {})
	if entry.is_empty():
		return
	entry.def = s
	match s.get("kind"):
		"meter":
			var max_value := maxf(float(s.max), 0.001)
			var fraction := clampf((float(s.value) - float(s.min)) / (max_value - float(s.min)), 0.0, 1.0)
			_set_bar(entry.bar, fraction, Color(str(s.color)) if fraction > LOW_FRACTION else LOW_COLOR)
			_set_low(entry.row, fraction <= LOW_FRACTION)
		"level":
			var lv: Dictionary = s.get("level", {})
			entry.label.text = "Nv %d" % int(lv.get("level", 1))
			_set_bar(entry.bar, float(lv.get("progress", 0.0)), Color(str(s.color)))
		_:
			if not animate:
				entry.shown_value = float(s.value)
				entry.label.text = PlayerStats.format_number(s.value)


## Animación de cambio: número que cuenta, "+50" flotante y un destello en la fila.
func _on_stat_changed(key: String, old_value: float, new_value: float) -> void:
	var entry: Dictionary = _rows.get(key, {})
	if entry.is_empty():
		return
	var delta := new_value - old_value
	var kind: String = entry.def.get("kind", "")
	# El desgaste del hambre (−0,5 por minuto) no merece animación.
	if kind == "meter" and absf(delta) < 1.0:
		return

	if kind == "counter":
		var tween := create_tween()
		tween.tween_method(func(v: float) -> void:
			entry.shown_value = v
			entry.label.text = PlayerStats.format_number(v), old_value, new_value, 0.6)

	var text := ("+" if delta > 0 else "−") + PlayerStats.format_number(absf(delta))
	if kind == "level":
		text += " xp"
	_float_text(entry.row, text, LOW_COLOR if delta < 0 else Color(str(entry.def.color)))
	var flash := create_tween()
	entry.row.modulate = Color(1.6, 1.6, 1.6)
	flash.tween_property(entry.row, "modulate", Color.WHITE, 0.4)


func _float_text(row: Control, text: String, color: Color) -> void:
	var label := _label(color)
	label.text = text
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	# Hermano del panel en el HUD (no hijo: el contenedor lo acomodaría) y
	# justo después de él, así queda por debajo del menú modal.
	var parent := get_parent()
	parent.add_child(label)
	parent.move_child(label, get_index() + 1)
	label.reset_size()
	# A la izquierda del panel, a la altura de la fila.
	label.position = Vector2(position.x - label.size.x - 4, row.global_position.y - 1)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 10, 1.2)
	tween.tween_property(label, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tween.chain().tween_callback(label.queue_free)


## Parpadeo suave de las filas con el valor bajo (hambre casi a 0).
func _set_low(row: Control, low: bool) -> void:
	row.set_meta(&"low", low)
	var any_low := false
	for entry: Dictionary in _rows.values():
		any_low = any_low or entry.row.get_meta(&"low", false)
	if any_low and _low_tween == null:
		_low_tween = create_tween().set_loops()
		_low_tween.tween_method(_pulse_low, 0.0, TAU, 1.2)
	elif not any_low and _low_tween:
		_low_tween.kill()
		_low_tween = null
		_pulse_low(PI / 2.0)


func _pulse_low(phase: float) -> void:
	for entry: Dictionary in _rows.values():
		var low: bool = entry.row.get_meta(&"low", false)
		entry.row.modulate.a = (0.55 + 0.45 * absf(sin(phase))) if low else 1.0


# --- Piezas ----------------------------------------------------------------------

func _icon(icon_name: String) -> Texture2D:
	if not _icons.has(icon_name):
		var path := ICON_DIR + icon_name + ".png"
		if not ResourceLoader.exists(path):
			path = ICON_DIR + FALLBACK_ICON + ".png"
		_icons[icon_name] = load(path)
	return _icons[icon_name]


func _label(color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color.lerp(TEXT_COLOR, 0.35))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _bar(bar_size: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.custom_minimum_size = bar_size
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.45)
	background.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", background)
	_set_bar(bar, 0.0, color)
	return bar


func _set_bar(bar: ProgressBar, fraction: float, color: Color) -> void:
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill").duplicate() if bar.has_theme_stylebox_override("fill") else StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	var tween := bar.create_tween()
	tween.tween_property(bar, "value", fraction, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.5)
	style.set_corner_radius_all(6)
	style.content_margin_left = 4
	style.content_margin_right = 5
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	style.anti_aliasing = true
	return style
