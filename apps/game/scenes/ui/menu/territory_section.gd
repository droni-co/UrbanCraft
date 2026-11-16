class_name TerritorySection
extends VBoxContainer
## Menú → Territorio: el mapa de sectores alrededor (los tuyos, los de otros y
## los libres), tu rango en cada uno y la renta por cobrar.

const RADIUS := 3
const CELL := 24.0
const RANK_COLORS: Array[Color] = [Color(1, 1, 1, 0.05), Color("3d587f"), Color("4f7fb8"), Color("5fa8a0"),
	Color("8fc46a"), Color("f2c14e")]

var _grid: GridContainer
var _info: Label
var _rent: Label
var _collect: Button
var _status: Label
var _selected := Vector2i(-1, -1)


func _ready() -> void:
	add_theme_constant_override("separation", 5)
	var title := Label.new()
	title.text = "Territorio"
	title.theme_type_variation = &"SectionTitle"
	add_child(title)
	GameWindow.hint(self, "La ciudad se divide en sectores. Lo que haces en uno te da influencia ahí: visitar lugares, trabajar, encargos, poner objetos. Con rango Conocido y tu bandera plantada, el sector es tuyo mientras nadie con bandera te supere. La influencia se apaga si no vuelves.")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_grid = GridContainer.new()
	_grid.columns = RADIUS * 2 + 1
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	row.add_child(_grid)

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 4)
	row.add_child(side)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 9)
	side.add_child(_info)
	side.add_child(HSeparator.new())
	_rent = Label.new()
	_rent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rent.add_theme_font_size_override("font_size", 9)
	side.add_child(_rent)
	_collect = GameWindow.small_button(side, "Cobrar la renta", _collect_rent, &"PrimaryButton")
	_collect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_status = Label.new()
	_status.theme_type_variation = &"HintLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	side.add_child(_status)

	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 8)
	add_child(legend)
	for i in range(1, RANK_COLORS.size()):
		legend.add_child(_legend(RANK_COLORS[i], "%s (%d)" % [Game.rank_name(i), int(Game.ranks[i].points)] if i < Game.ranks.size() else ""))
	GameWindow.hint(self, "Borde dorado: es tuyo. Borde rojo: es de otro jugador. Tu rango en un sector te da descuento en sus tiendas.")

	Game.territory_changed.connect(_refresh)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_status.visible = false
			_selected = Vector2i(-1, -1)
			_refresh()
			Game.refresh_territory())
	_refresh()


func _legend(color: Color, text: String) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(9, 9)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(swatch)
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HintLabel"
	label.add_theme_font_size_override("font_size", 8)
	box.add_child(label)
	return box


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	GameWindow.clear(_grid)
	var here: Dictionary = Game.territory.get("here", {})
	if here.is_empty():
		_info.text = "Cargando el mapa de sectores…"
		_rent.text = ""
		_collect.visible = false
		return
	var center := Vector2i(int(here.sx), int(here.sy))
	if _selected == Vector2i(-1, -1):
		_selected = center
	var by_cell := {}
	for s: Dictionary in Game.territory.get("sectors", []):
		by_cell[Vector2i(int(s.sx), int(s.sy))] = s
	for dy in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var cell := center + Vector2i(dx, dy)
			_grid.add_child(_sector_button(cell, by_cell.get(cell, {}), cell == center))
	_show_info(by_cell.get(_selected, {}))

	var rent: Dictionary = Game.territory.get("rent", {})
	var sectors := int(rent.get("sectors", 0))
	if sectors == 0:
		_rent.text = "Renta: todavía no dominas ningún sector."
	else:
		_rent.text = "Dominas %d %s: $%d al día.\nPor cobrar: $%s (se acumula hasta 3 días)." % [sectors,
			"sector" if sectors == 1 else "sectores", int(rent.get("perDay", 0)), PlayerStats.format_number(rent.get("amount", 0))]
	_collect.visible = sectors > 0
	_collect.disabled = int(rent.get("amount", 0)) <= 0


func _sector_button(cell: Vector2i, sector: Dictionary, is_here: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(CELL, CELL)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = str(sector.get("name", "Sector sin explorar"))
	var rank := int(sector.get("rank", 0))
	var style := StyleBoxFlat.new()
	style.bg_color = RANK_COLORS[clampi(rank, 0, RANK_COLORS.size() - 1)]
	style.set_corner_radius_all(4)
	style.anti_aliasing = true
	if sector.get("owner") is Dictionary:
		style.border_color = MenuTheme.GOLD if sector.get("mine", false) else MenuTheme.DANGER
		style.set_border_width_all(2)
	if cell == _selected:
		style.border_color = Color.WHITE
		style.set_border_width_all(2)
	for state: String in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, style)
	if is_here:
		button.text = "Tú"
		button.add_theme_font_size_override("font_size", 8)
		button.add_theme_color_override("font_color", Color.WHITE)
	elif sector.get("mine", false):
		button.icon = GameArt.medal("bandera")
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.pressed.connect(func() -> void:
		_selected = cell
		_refresh())
	return button


func _show_info(sector: Dictionary) -> void:
	if sector.is_empty():
		_info.text = "Sector sin explorar.\nNo tienes influencia aquí todavía."
		return
	var owner: Variant = sector.get("owner")
	var who := "Sin dueño: Don Gris le tiene echado el ojo."
	if owner is Dictionary:
		who = "Es tuyo." if sector.get("mine", false) else "Lo domina %s." % owner.name
	var rank := int(sector.rank)
	var next := ""
	if rank + 1 < Game.ranks.size():
		next = "\nPara %s te faltan %d." % [Game.rank_name(rank + 1), int(Game.ranks[rank + 1].points) - int(sector.points)]
	_info.text = "%s\nTu rango: %s (%d de influencia).%s\n%s" % [sector.name, Game.rank_name(rank), int(sector.points), next, who]


func _collect_rent() -> void:
	var res := await Game.collect_rent()
	_status.visible = not res.ok
	if not res.ok:
		_status.text = str(res.message)
		_status.add_theme_color_override("font_color", MenuTheme.DANGER)
	_refresh()
