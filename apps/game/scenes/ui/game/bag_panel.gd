class_name BagPanel
extends GameWindow
## El morral: lo que llevas (comer, colocar en el mapa) y la pestaña Fabricar
## con las recetas. Se abre con la tecla I o el botón de la mochila.

## El jugador eligió colocar un objeto en el mapa (la ventana ya se cerró).
signal place_requested(item_key: String)

const SLOT := Vector2(34, 34)
const COLUMNS := 6
const KIND_NAMES := {"food": "Comida", "material": "Material", "tool": "Herramienta", "placeable": "Para colocar"}
const STATION_NAMES := {"mesa": "Mesa de trabajo", "parrilla": "Parrilla"}

var _tab := 0
var _selected := ""
var _busy := false

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _grid: GridContainer
var _capacity: Label
var _detail: VBoxContainer
var _recipes: VBoxContainer
var _status: Label


func _build() -> void:
	panel_size = Vector2(440, 300)
	title_text = "Morral"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	body.add_child(tabs)
	var group := ButtonGroup.new()
	for i in 2:
		var button := Button.new()
		button.text = ["Lo que llevo", "Fabricar"][i]
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = &"NavButton"
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			_tab = i
			_refresh())
		tabs.add_child(button)
		_tab_buttons.append(button)
	_capacity = Label.new()
	_capacity.theme_type_variation = &"HintLabel"
	_capacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tabs.add_child(_capacity)

	# Página 1: rejilla + detalle
	var bag := HBoxContainer.new()
	bag.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag.add_theme_constant_override("separation", 8)
	body.add_child(bag)
	var scroll := TouchScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x = COLUMNS * (SLOT.x + 3) + 8
	bag.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	scroll.add_child(_grid)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 4)
	bag.add_child(_detail)
	_pages.append(bag)

	# Página 2: recetas
	var craft := VBoxContainer.new()
	craft.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(craft)
	_recipes = GameWindow.scroll_list(craft, 4)
	_pages.append(craft)

	_status = Label.new()
	_status.theme_type_variation = &"HintLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	body.add_child(_status)
	Game.changed.connect(func() -> void:
		if visible:
			_refresh())


func open_bag(tab := 0) -> void:
	_tab = tab
	_status.visible = false
	_refresh()
	open()
	Game.refresh_jobs()  # de paso, el morral al día (por si cambió por el multijugador)


func _refresh() -> void:
	for i in _pages.size():
		_pages[i].visible = i == _tab
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
	_capacity.text = "%d / %d espacios" % [Game.inventory.size(), Game.slots]
	if _tab == 0:
		_fill_bag()
	else:
		_fill_recipes()


# --- Lo que llevo -----------------------------------------------------------------

func _fill_bag() -> void:
	GameWindow.clear(_grid)
	var keys: Array = Game.inventory.keys()
	var order := {"food": 0, "placeable": 1, "tool": 2, "material": 3}
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ka: int = order.get(Game.item(a).kind, 9)
		var kb: int = order.get(Game.item(b).kind, 9)
		return ka < kb if ka != kb else Game.item_name(a) < Game.item_name(b))
	if not Game.inventory.has(_selected):
		_selected = str(keys[0]) if not keys.is_empty() else ""
	for i in maxi(Game.slots, keys.size()):
		_grid.add_child(_slot(str(keys[i]) if i < keys.size() else ""))
	_fill_detail()


func _slot(key: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = SLOT
	button.theme_type_variation = &"CardButton"
	button.focus_mode = Control.FOCUS_NONE
	if key.is_empty():
		button.disabled = true
		return button
	button.toggle_mode = true
	button.button_pressed = key == _selected
	button.icon = GameArt.item(key)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.tooltip_text = Game.item_name(key)
	button.pressed.connect(func() -> void:
		_selected = key
		_fill_bag())
	var qty := Label.new()
	qty.text = str(Game.count(key))
	qty.add_theme_font_override("font", UiArt.FONT_BOLD)
	qty.add_theme_font_size_override("font_size", 8)
	qty.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	qty.add_theme_constant_override("outline_size", 3)
	qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qty.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	qty.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	qty.grow_vertical = Control.GROW_DIRECTION_BEGIN
	qty.offset_right = -3
	qty.offset_bottom = -1
	button.add_child(qty)
	return button


func _fill_detail() -> void:
	GameWindow.clear(_detail)
	if _selected.is_empty():
		GameWindow.hint(_detail, "Tu morral está vacío.\n\nRebusca en árboles y arbustos, compra en las tiendas o fabrica cosas.")
		return
	var def := Game.item(_selected)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	_detail.add_child(head)
	var icon := TextureRect.new()
	icon.texture = GameArt.item(_selected)
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	var name_label := Label.new()
	name_label.text = "%s  ×%d" % [def.name, Game.count(_selected)]
	name_label.theme_type_variation = &"SectionTitle"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(name_label)
	var kind := Label.new()
	kind.text = str(KIND_NAMES.get(def.kind, ""))
	kind.theme_type_variation = &"HintLabel"
	names.add_child(kind)

	var desc := Label.new()
	desc.text = str(def.desc)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 9)
	_detail.add_child(desc)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 5)
	_detail.add_child(buttons)
	match def.kind:
		"food":
			GameWindow.hint(_detail, "Quita %d de hambre." % int(def.get("hunger", 0)))
			GameWindow.small_button(buttons, "Comer", _eat, &"PrimaryButton")
		"placeable":
			GameWindow.hint(_detail, "Se coloca en la casilla que tienes al frente: un andén o zona verde libre. Lo verán los demás jugadores.")
			GameWindow.small_button(buttons, "Colocar en el mapa", func() -> void:
				var key := _selected
				close()
				place_requested.emit(key), &"PrimaryButton")
		"tool":
			if def.get("slots") != null:
				GameWindow.hint(_detail, "Mientras lo lleves, tu morral tiene %d espacios más." % int(def.slots))
	GameWindow.hint(_detail, "Precio de referencia: $%d. Las tiendas pagan según lo que necesiten." % int(def.price))


func _eat() -> void:
	_run(func() -> Dictionary: return await Game.use_item(_selected))


# --- Fabricar ---------------------------------------------------------------------

func _fill_recipes() -> void:
	GameWindow.clear(_recipes)
	var list := Game.recipes.duplicate()
	# Primero lo que ya se puede hacer.
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := Game.can_craft(a)
		var cb := Game.can_craft(b)
		return ca and not cb if ca != cb else int(a.level) < int(b.level))
	for recipe: Dictionary in list:
		_recipes.add_child(_recipe_row(recipe))


func _recipe_row(recipe: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.22)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	var output := str(recipe.output)
	var qty := int(recipe.get("qty", 1))
	var ready := Game.can_craft(recipe)
	var head := GameWindow.row(GameArt.item(output), "%s%s" % [Game.item_name(output), "  ×%d" % qty if qty > 1 else ""])
	head.tooltip_text = str(Game.item(output).desc)
	column.add_child(head)
	GameWindow.small_button(head, "Fabricar", _craft.bind(str(recipe.key)), &"PrimaryButton").disabled = not ready

	var parts: PackedStringArray = []
	for key: String in recipe.inputs:
		parts.append("%d/%d %s" % [Game.count(key), int(recipe.inputs[key]), Game.item_name(key)])
	var needs := Label.new()
	needs.text = "  ·  ".join(parts)
	needs.add_theme_font_size_override("font_size", 8)
	needs.add_theme_color_override("font_color", MenuTheme.SUCCESS if ready else MenuTheme.TEXT_DIM)
	needs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(needs)

	var extra: PackedStringArray = []
	if recipe.get("station") != null:
		extra.append("Junto a: %s" % STATION_NAMES.get(recipe.station, recipe.station))
	if recipe.get("tool") != null:
		extra.append("Con: %s" % Game.item_name(str(recipe.tool)))
	if int(recipe.level) > 1:
		extra.append("Nivel %d" % int(recipe.level))
	if not extra.is_empty():
		var label := Label.new()
		label.text = "  ·  ".join(extra)
		label.add_theme_font_size_override("font_size", 8)
		var missing := Game.level() < int(recipe.level) or (recipe.get("tool") != null and Game.count(str(recipe.tool)) == 0)
		label.add_theme_color_override("font_color", MenuTheme.DANGER if missing else MenuTheme.GOLD)
		column.add_child(label)
	return panel


func _craft(key: String) -> void:
	_run(func() -> Dictionary: return await Game.craft(key))


func _run(action: Callable) -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary = await action.call()
	_busy = false
	_status.visible = not res.ok
	if not res.ok:
		_status.text = str(res.message)
		_status.add_theme_color_override("font_color", MenuTheme.DANGER)
	if visible:
		_refresh()
