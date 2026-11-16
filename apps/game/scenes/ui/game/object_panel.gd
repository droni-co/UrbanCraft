class_name ObjectPanel
extends GameWindow
## Ventana de un objeto del mapa (los que dejan los jugadores): regar una
## matera, leer o cambiar un letrero, la caja de trueque, el puesto de venta…
## Las acciones van a Game.object_action(); cada respuesta trae el objeto y su
## detalle al día (ver WorldObjects.act en el backend).

const KIND_TEXT := {
	"matera": "Riégala una vez al día. Con dos riegos florece y da flores.",
	"banca": "Una banca. Siéntate un rato: el barrio se ve distinto desde aquí.",
	"letrero": "Un letrero para el que pase.",
	"caja": "Caja de trueque: deja algo que no uses y llévate lo que te sirva.",
	"puesto": "Puesto de venta. La gente del barrio también compra aquí.",
	"parrilla": "Parrilla: quédate cerca y abre Fabricar en el morral para asar.",
	"mesa": "Mesa de trabajo: quédate cerca y abre Fabricar en el morral.",
	"bandera": "Con esta bandera su dueño pelea por el dominio del sector.",
	"farol": "Un farol. De noche se agradece.",
	"fiesta": "La mesa de la fiesta. Hay torta para todos.",
}

var _object := {}
var _detail := {}
var _busy := false

var _icon: TextureRect
var _info: Label
var _owner: Label
var _content: VBoxContainer
var _status: Label
var _price: SpinBox


func _build() -> void:
	panel_size = Vector2(400, 280)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	body.add_child(head)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(44, 44)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_icon)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	head.add_child(column)
	_owner = Label.new()
	_owner.add_theme_font_override("font", UiArt.FONT_BOLD)
	_owner.add_theme_color_override("font_color", MenuTheme.GOLD.lightened(0.2))
	column.add_child(_owner)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 9)
	column.add_child(_info)

	_content = GameWindow.scroll_list(body)
	_status = Label.new()
	_status.theme_type_variation = &"HintLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	body.add_child(_status)


func open_object(object: Dictionary) -> void:
	_object = object
	_detail = {}
	_status.visible = false
	_refresh()
	open()
	_act("look")


func _is_owner() -> bool:
	return bool(_detail.get("isOwner", int(_object.get("owner", 0)) == Online.my_id))


func _refresh() -> void:
	var kind := str(_object.get("kind", ""))
	title_text = Game.item_name(kind)
	_icon.texture = GameArt.object(kind, _object.get("state", {}))
	_owner.text = "Es tuyo" if _is_owner() else "De %s" % _object.get("ownerName", "otro jugador")
	_info.text = str(KIND_TEXT.get(kind, ""))
	GameWindow.clear(_content)
	if _detail.is_empty():
		GameWindow.hint(_content, "Mirando…")
		return
	match kind:
		"matera":
			_fill_matera()
		"letrero":
			_fill_sign()
		"caja":
			_fill_box()
		"puesto":
			_fill_stall()
	if _is_owner():
		var footer := HBoxContainer.new()
		_content.add_child(footer)
		GameWindow.small_button(footer, "Recoger y guardar en el morral", func() -> void: _act("pickup"))


func _fill_matera() -> void:
	var stage := int(_detail.get("stage", 0))
	GameWindow.hint(_content, ["Solo tiene tierra. Le falta agua.", "Ya tiene brotes. Un riego más y florece.", "Está florecida."][clampi(stage, 0, 2)])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	_content.add_child(row)
	GameWindow.small_button(row, "Regar", func() -> void: _act("water"), &"PrimaryButton").disabled = not _detail.get("canWater", false)
	if stage >= 2:
		GameWindow.small_button(row, "Llevarse una flor", func() -> void: _act("pick")).disabled = not _detail.get("canPick", false)
	if not _detail.get("canWater", false):
		GameWindow.hint(_content, "Ya la regaste hoy.")


func _fill_sign() -> void:
	var phrase := int(_detail.get("phrase", 0))
	var text := Label.new()
	text.text = "«%s»" % (Game.sign_phrases[phrase] if phrase < Game.sign_phrases.size() else "")
	text.theme_type_variation = &"SectionTitle"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(text)
	if not _is_owner():
		return
	GameWindow.hint(_content, "Elige qué dice:")
	for i in Game.sign_phrases.size():
		var button := GameWindow.small_button(_content, str(Game.sign_phrases[i]), func() -> void: _act("set", {"phrase": i}))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = i == phrase


func _fill_box() -> void:
	var items: Dictionary = _detail.get("items", {})
	_section("En la caja (%d/%d)" % [items.size(), int(_detail.get("stacks", 6))])
	if items.is_empty():
		GameWindow.hint(_content, "Está vacía. Sé el primero en dejar algo.")
	for key: String in items:
		var row := GameWindow.row(GameArt.item(key), "%s  ×%d" % [Game.item_name(key), int(items[key])])
		GameWindow.small_button(row, "Tomar", func() -> void: _act("take", {"item": key, "qty": 1}))
		_content.add_child(row)
	_section("Dejar algo de tu morral")
	_inventory_rows(func(key: String, qty: int) -> void: _act("put", {"item": key, "qty": qty}), "Dejar")


func _fill_stall() -> void:
	var stock: Array = _detail.get("stock", [])
	var owner := _is_owner()
	if owner:
		var till := int(_detail.get("till", 0))
		var row := GameWindow.row(UiArt.icon("money"), "En la caja del puesto", "$%s" % PlayerStats.format_number(till), Color("ffe08a"))
		GameWindow.small_button(row, "Cobrar", func() -> void: _act("collect"), &"PrimaryButton").disabled = till <= 0
		_content.add_child(row)
	_section("En venta (%d/%d)" % [stock.size(), int(_detail.get("products", 6))])
	if stock.is_empty():
		GameWindow.hint(_content, "No hay nada a la venta." if not owner else "Surte tu puesto con lo que llevas en el morral.")
	var money := int(PlayerStats.value("money"))
	for entry: Dictionary in stock:
		var key := str(entry.item)
		var price := int(entry.price)
		var row := GameWindow.row(GameArt.item(key), "%s  ×%d" % [Game.item_name(key), int(entry.qty)], "$%d" % price, Color("ffe08a"))
		if owner:
			GameWindow.small_button(row, "Retirar", func() -> void: _act("unstock", {"item": key}))
		else:
			GameWindow.small_button(row, "Comprar", func() -> void: _act("buy", {"item": key, "qty": 1}), &"PrimaryButton").disabled = money < price
		_content.add_child(row)
	if not owner:
		return
	_section("Surtir con tu morral")
	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 5)
	_content.add_child(price_row)
	var label := Label.new()
	label.text = "Precio por unidad: $"
	label.add_theme_font_size_override("font_size", 9)
	price_row.add_child(label)
	var previous := _price.value if _price else 0.0
	_price = SpinBox.new()
	_price.min_value = 1
	_price.max_value = 2000
	_price.value = previous if previous > 0.0 else 20
	_price.custom_minimum_size = Vector2(70, 20)
	price_row.add_child(_price)
	GameWindow.hint(_content, "Al precio de referencia se vende rápido; al doble, despacio; al triple, casi nadie compra.")
	_inventory_rows(func(key: String, qty: int) -> void:
		_act("stock", {"item": key, "qty": qty, "price": int(_price.value)}), "Poner", true)


func _section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiArt.FONT_BOLD)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", MenuTheme.GOLD)
	_content.add_child(label)


func _inventory_rows(action: Callable, verb: String, show_price := false) -> void:
	if Game.inventory.is_empty():
		GameWindow.hint(_content, "No llevas nada.")
	for key: String in Game.inventory:
		var qty := Game.count(key)
		var row := GameWindow.row(GameArt.item(key), "%s  ×%d" % [Game.item_name(key), qty],
			"ref. $%d" % int(Game.item(key).price) if show_price else "")
		GameWindow.small_button(row, verb, action.bind(key, 1))
		if qty >= 5:
			GameWindow.small_button(row, "×5", action.bind(key, 5))
		_content.add_child(row)


func _act(action: String, args := {}) -> void:
	if _busy:
		return
	_busy = true
	var res := await Game.object_action(int(_object.get("id", 0)), action, args)
	_busy = false
	_status.visible = not res.ok or res.data.get("message") != null
	if not res.ok:
		_status.text = str(res.message)
		_status.add_theme_color_override("font_color", MenuTheme.DANGER)
		if res.code == "unknown_object":
			close()
		return
	if res.data.get("removed", false):
		close()
		return
	if res.data.get("message") != null:
		_status.text = str(res.data.message)
		_status.add_theme_color_override("font_color", MenuTheme.SUCCESS)
	if res.data.get("object") is Dictionary:
		_object = res.data.object
	if res.data.get("detail") is Dictionary:
		_detail = res.data.detail
	if visible:
		_refresh()
