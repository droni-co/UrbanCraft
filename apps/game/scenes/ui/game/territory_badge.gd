class_name TerritoryBadge
extends PanelContainer
## Tu rango en el sector donde estás, siempre a la vista bajo el minimapa:
## nombre del sector, rango (con su color), barra de influencia hacia el
## siguiente rango y de quién es. Al entrar a otro sector o cambiar de rango
## destella para que se note. Tocarla abre Menú → Territorio.

signal pressed

const WIDTH := 136.0

var _sector_key := Vector2i(-99999, -99999)
var _rank := -1
var _medal: TextureRect
var _name: Label
var _rank_label: Label
var _points: Label
var _bar: ProgressBar
var _owner: Label
var _style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Tu rango en este sector (toca para ver el territorio)"
	custom_minimum_size.x = WIDTH
	_style = UiArt.chip(6, 0.86)
	_style.border_color = Color(MenuTheme.GOLD, 0.55)
	_style.set_border_width_all(1)
	_style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", _style)
	visible = false

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_medal = TextureRect.new()
	_medal.custom_minimum_size = Vector2(22, 22)
	_medal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_medal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_medal)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	_name = _label(column, 7, MenuTheme.TEXT_DIM)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 3)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	_rank_label = _label(head, 10, MenuTheme.TEXT, UiArt.FONT_DISPLAY)
	_rank_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING  # el rango siempre entero
	_points = _label(head, 7, MenuTheme.TEXT_DIM)
	_points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_points.size_flags_vertical = Control.SIZE_SHRINK_END

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 4)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.45)
	back.set_corner_radius_all(2)
	_bar.add_theme_stylebox_override("background", back)
	column.add_child(_bar)
	_owner = _label(column, 7, MenuTheme.TEXT_DIM)

	Game.territory_changed.connect(_refresh)
	Game.changed.connect(_refresh)
	_refresh()


func _label(parent: Control, font_size: int, color: Color, font: Font = UiArt.FONT_BOLD) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", -3)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) \
			or (event is InputEventScreenTouch and not event.pressed):
		accept_event()
		pressed.emit()


func _refresh() -> void:
	var sector := Game.current_sector()
	visible = Game.ready_to_play and not sector.is_empty()
	if not visible:
		return
	var rank := int(sector.get("rank", 0))
	var points := int(sector.get("points", 0))
	var color := rank_color(rank)
	var mine: bool = sector.get("mine", false)
	var owner: Variant = sector.get("owner")

	_medal.texture = GameArt.medal("corona" if mine else "bandera")
	_medal.modulate = Color.WHITE if rank > 0 or mine else Color(1, 1, 1, 0.55)
	_name.text = str(sector.get("name", ""))
	_rank_label.text = Game.rank_name(rank) if not Game.rank_name(rank).is_empty() else "Sin rango"
	_rank_label.add_theme_color_override("font_color", color.lightened(0.25))

	var next := rank + 1
	if next < Game.ranks.size():
		var from := int(Game.ranks[rank].points) if rank < Game.ranks.size() else 0
		var to := int(Game.ranks[next].points)
		_bar.min_value = from
		_bar.max_value = maxf(to, from + 1)
		_bar.value = clampi(points, from, to)
		_points.text = "%d / %d" % [points, to]
		_bar.tooltip_text = "Para %s te faltan %d de influencia" % [Game.rank_name(next), to - points]
	else:
		_bar.min_value = 0
		_bar.max_value = 1
		_bar.value = 1
		_points.text = "%d · máximo" % points
	var fill := StyleBoxFlat.new()
	fill.bg_color = color.lightened(0.15)
	fill.set_corner_radius_all(2)
	_bar.add_theme_stylebox_override("fill", fill)

	if mine:
		_owner.text = "Este sector es tuyo"
		_owner.add_theme_color_override("font_color", MenuTheme.GOLD.lightened(0.2))
	elif owner is Dictionary:
		_owner.text = "Lo domina %s" % owner.name
		_owner.add_theme_color_override("font_color", MenuTheme.DANGER.lightened(0.2))
	else:
		_owner.text = "Sin dueño"
		_owner.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	_style.border_color = Color(MenuTheme.GOLD, 0.9) if mine else Color(color.lightened(0.2), 0.7)

	# Entraste a otro sector o subiste de rango: destello.
	var key := Vector2i(int(sector.sx), int(sector.sy))
	if key != _sector_key or rank != _rank:
		var first := _rank == -1
		_sector_key = key
		_rank = rank
		if not first:
			_flash()


func _flash() -> void:
	pivot_offset = size / 2.0
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(self, "modulate", Color(1.5, 1.4, 1.1), 0.12)
	tween.tween_property(self, "scale", Vector2.ONE, 0.25)
	tween.parallel().tween_property(self, "modulate", Color.WHITE, 0.4)


## Color de un rango (el mismo del mapa de sectores en Menú → Territorio).
static func rank_color(rank: int) -> Color:
	var colors := TerritorySection.RANK_COLORS
	if rank <= 0:
		return Color("9aa6b8")
	return colors[clampi(rank, 0, colors.size() - 1)]
