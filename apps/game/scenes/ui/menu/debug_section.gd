class_name DebugSection
extends VBoxContainer
## Herramientas de depuración del menú (solo builds de depuración y servidores
## con DEV_LOGIN_ENABLED, en local): cambiar stats para probar el HUD.


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	if theme == null:
		theme = MenuTheme.build()

	var title := Label.new()
	title.text = "Depuración"
	title.theme_type_variation = &"SectionTitle"
	add_child(title)

	var hint := Label.new()
	hint.text = "Cambia los stats en el servidor (solo en desarrollo). Cierra el menú para ver las animaciones."
	hint.theme_type_variation = &"HintLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	_button(grid, "+100 dinero", func() -> void: PlayerStats.dev_change("money", 100))
	_button(grid, "−50 dinero", func() -> void: PlayerStats.dev_change("money", -50))
	_button(grid, "+60 xp", func() -> void: PlayerStats.dev_change("xp", 60))
	_button(grid, "+500 xp", func() -> void: PlayerStats.dev_change("xp", 500))
	_button(grid, "−30 hambre", func() -> void: PlayerStats.dev_change("hunger", -30))
	_button(grid, "Llenar hambre", func() -> void: PlayerStats.dev_change("hunger", 0, 100))
	_button(grid, "Reiniciar stats", _reset)


func _reset() -> void:
	for key in ["hunger", "xp", "money"]:
		var stat := PlayerStats.get_stat(key)
		if not stat.is_empty():
			await PlayerStats.dev_change(key, 0, 100 if key != "xp" else 0)


func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 24
	button.pressed.connect(action)
	parent.add_child(button)
