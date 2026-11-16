class_name PlacePanel
extends GameWindow
## Ventana de un lugar del mapa: quién atiende, y lo que se puede hacer ahí:
## comprar, vender, trabajar un turno, servicios (estudiar, entrenar…), cumplir
## pasos de encargos, hablar con personajes de la historia y pedir encargos.
## Los datos vienen de Game.visit() (ver GameService.#placeView en el backend).

const TABS := ["Comprar", "Vender", "Trabajo", "Encargos"]

var _place := {}
var _tab := 0
var _busy := false

var _portrait: TextureRect
var _who: Label
var _greeting: Label
var _sector: Label
var _actions: HFlowContainer
var _tab_bar: HBoxContainer
var _tab_buttons: Array[Button] = []
var _list: VBoxContainer
var _status: Label


func _build() -> void:
	panel_size = Vector2(440, 300)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	body.add_child(head)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(46, 46)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	head.add_child(_portrait)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	head.add_child(column)
	_who = Label.new()
	_who.add_theme_font_override("font", UiArt.FONT_BOLD)
	_who.add_theme_color_override("font_color", MenuTheme.GOLD.lightened(0.2))
	column.add_child(_who)
	_greeting = Label.new()
	_greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_greeting.add_theme_font_size_override("font_size", 9)
	column.add_child(_greeting)
	_sector = Label.new()
	_sector.theme_type_variation = &"HintLabel"
	_sector.add_theme_font_size_override("font_size", 8)
	column.add_child(_sector)

	_actions = HFlowContainer.new()
	_actions.add_theme_constant_override("h_separation", 5)
	_actions.add_theme_constant_override("v_separation", 3)
	body.add_child(_actions)

	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 3)
	body.add_child(_tab_bar)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var button := Button.new()
		button.text = TABS[i]
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = &"NavButton"
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 9)
		button.pressed.connect(func() -> void:
			_tab = i
			_fill())
		_tab_bar.add_child(button)
		_tab_buttons.append(button)

	_list = GameWindow.scroll_list(body)
	_status = Label.new()
	_status.theme_type_variation = &"HintLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	body.add_child(_status)


func open_place(place: Dictionary) -> void:
	_place = place
	_status.visible = false
	# Pestaña inicial: lo primero que el lugar ofrece.
	_tab = 0 if not place.get("sells", []).is_empty() else (2 if place.get("work") != null or not place.get("services", []).is_empty() else 3)
	_refresh()
	open()


func _poi() -> Dictionary:
	var poi: Dictionary = _place.get("poi", {})
	return {"id": poi.get("id", ""), "cx": int(poi.get("cx", 0)), "cy": int(poi.get("cy", 0))}


func _refresh() -> void:
	var poi: Dictionary = _place.get("poi", {})
	var npc: Dictionary = _place.get("npc", {})
	var sector: Dictionary = _place.get("sector", {})
	title_text = str(poi.get("name", "Lugar"))
	_portrait.texture = GameArt.portrait(str(npc.get("portrait", "vecino")))
	_who.text = "%s · %s, %s" % [_place.get("label", ""), npc.get("name", ""), npc.get("role", "")]
	_greeting.text = "«%s»" % npc.get("greeting", "")
	var discount := float(sector.get("discount", 0.0))
	_sector.text = "%s · %s (%d)%s" % [sector.get("name", ""), sector.get("rankName", ""), int(sector.get("points", 0)),
		" · descuento del %d%%" % roundi(discount * 100.0) if discount > 0.0 else ""]

	GameWindow.clear(_actions)
	var talk: Variant = _place.get("talk")
	if talk is Dictionary:
		var who := Game.npc(str(talk.npc))
		var button := GameWindow.small_button(_actions, "Hablar con %s" % who.name, _talk, &"PrimaryButton")
		button.icon = GameArt.portrait(str(who.portrait))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 16)
	for step: Dictionary in _place.get("jobSteps", []):
		var button := GameWindow.small_button(_actions, str(step.label), _job_step.bind(int(step.id)), &"PrimaryButton")
		button.tooltip_text = str(step.title)
	_actions.visible = _actions.get_child_count() > 0
	_fill()


func _fill() -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
	GameWindow.clear(_list)
	match _tab:
		0:
			_fill_buy()
		1:
			_fill_sell()
		2:
			_fill_work()
		3:
			_fill_jobs()


func _fill_buy() -> void:
	var sells: Array = _place.get("sells", [])
	if sells.is_empty():
		GameWindow.hint(_list, "Aquí no venden nada.")
		return
	var money := int(PlayerStats.value("money"))
	for offer: Dictionary in sells:
		var key := str(offer.item)
		var def := Game.item(key)
		var price := int(offer.price)
		var owned := Game.count(key)
		var row := GameWindow.row(GameArt.item(key), "%s%s" % [def.name, "  (tienes %d)" % owned if owned > 0 else ""],
			"$%d" % price, Color("ffe08a") if money >= price else MenuTheme.DANGER)
		row.tooltip_text = _item_tooltip(def)
		GameWindow.small_button(row, "Comprar", _trade.bind("buy", key, 1)).disabled = money < price
		GameWindow.small_button(row, "×5", _trade.bind("buy", key, 5)).disabled = money < price * 5
		_list.add_child(row)


func _fill_sell() -> void:
	var buys: Array = _place.get("buys", [])
	if buys.is_empty():
		GameWindow.hint(_list, "No tienes nada que compren aquí.")
		return
	buys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.price) > int(b.price))
	for offer: Dictionary in buys:
		var key := str(offer.item)
		var def := Game.item(key)
		var qty := int(offer.qty)
		var good := int(offer.price) >= int(float(def.price) * 0.7)
		var row := GameWindow.row(GameArt.item(key), "%s  ×%d" % [def.name, qty], "$%d c/u" % int(offer.price),
			MenuTheme.SUCCESS if good else Color("ffe08a"))
		row.tooltip_text = "Aquí lo pagan muy bien." if good else "Precio normal. En otro lugar puede valer más."
		GameWindow.small_button(row, "Vender", _trade.bind("sell", key, 1))
		if qty > 1:
			GameWindow.small_button(row, "Todo", _trade.bind("sell", key, qty))
		_list.add_child(row)


func _fill_work() -> void:
	var work: Variant = _place.get("work")
	var services: Array = _place.get("services", [])
	if work == null and services.is_empty():
		GameWindow.hint(_list, "Aquí no hay trabajo ni servicios. Pero el lugar es agradable.")
		return
	if work is Dictionary:
		var wait := int(work.wait)
		var row := GameWindow.row(UiArt.icon("money"), str(work.label), "$%d–%d" % [int(work.pay[0]), int(work.pay[1])], Color("ffe08a"))
		var button := GameWindow.small_button(row, "Trabajar" if wait == 0 else "En %s" % GameWindow.format_wait(wait), _work, &"PrimaryButton")
		button.disabled = wait > 0
		_list.add_child(row)
		GameWindow.hint(_list, "Un turno paga al momento y te da un poco de hambre. Con el hambre en cero rindes la mitad.")
	for service: Dictionary in services:
		var wait := int(service.wait)
		var cost := int(service.cost)
		var row := GameWindow.row(UiArt.icon("xp"), str(service.label), "%s · +%d xp" % ["$%d" % cost if cost > 0 else "gratis", int(service.xp)], Color("9fd0ff"))
		var button := GameWindow.small_button(row, "Hacer" if wait == 0 else "En %s" % GameWindow.format_wait(wait), _service.bind(str(service.key)))
		button.disabled = wait > 0 or PlayerStats.value("money") < cost
		_list.add_child(row)


func _fill_jobs() -> void:
	JobList.fill(_list, _run_job)


func _item_tooltip(def: Dictionary) -> String:
	var text := str(def.get("desc", ""))
	if def.get("hunger") != null:
		text += "\nQuita %d de hambre." % int(def.hunger)
	return text


# --- Acciones ---------------------------------------------------------------------

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
	if res.ok and res.data.get("place") is Dictionary:
		_place = res.data.place
	if visible:
		_refresh()


func _trade(kind: String, key: String, qty: int) -> void:
	_run(func() -> Dictionary:
		if kind == "buy":
			return await Game.buy(_poi(), key, qty)
		return await Game.sell(_poi(), key, qty))


func _work() -> void:
	_run(func() -> Dictionary: return await Game.work(_poi()))


func _service(key: String) -> void:
	_run(func() -> Dictionary: return await Game.service(_poi(), key))


func _talk() -> void:
	_run(func() -> Dictionary: return await Game.story_talk(_poi()))


func _job_step(id: int) -> void:
	_run(func() -> Dictionary: return await Game.job_step(id, _poi()))


func _run_job(action: Callable) -> void:
	_run(action)
