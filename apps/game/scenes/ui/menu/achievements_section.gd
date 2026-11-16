class_name AchievementsSection
extends VBoxContainer
## Menú → Logros: todas las medallas, por familia. Las conseguidas brillan con
## el color de su nivel; las otras muestran cuánto falta.

const MEDAL := Vector2(34, 34)

var _summary: Label
var _detail: Label
var _list: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 5)
	var title := Label.new()
	title.text = "Logros"
	title.theme_type_variation = &"SectionTitle"
	add_child(title)
	_summary = Label.new()
	_summary.theme_type_variation = &"HintLabel"
	add_child(_summary)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 9)
	_detail.custom_minimum_size.y = 26
	_detail.text = "Toca una medalla para ver cómo se consigue."
	add_child(_detail)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	add_child(_list)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_refresh())
	_refresh()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	GameWindow.clear(_list)
	var total := Game.achievement_defs.size()
	_summary.text = "%d de %d conseguidos" % [Game.achievements.size(), total]
	# Una fila por familia, con sus niveles en orden.
	var families := {}
	var order: Array[String] = []
	for def: Dictionary in Game.achievement_defs:
		var family := str(def.family)
		if not families.has(family):
			families[family] = []
			order.append(family)
		families[family].append(def)
	for family in order:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_list.add_child(row)
		var defs: Array = families[family]
		for def: Dictionary in defs:
			row.add_child(_medal(def))
		var first: Dictionary = defs[0]
		var value := float(Game.counters.get(str(first.counter), 0.0))
		var next: Variant = null
		for def: Dictionary in defs:
			if not Game.achievements.has(str(def.key)):
				next = def
				break
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 8)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if next is Dictionary:
			label.text = "%s\n%s / %s" % [next.desc, PlayerStats.format_number(minf(value, float(next.count))), PlayerStats.format_number(next.count)]
			label.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
		else:
			label.text = "¡Completo!"
			label.add_theme_color_override("font_color", MenuTheme.SUCCESS)
		row.add_child(label)


func _medal(def: Dictionary) -> Control:
	var unlocked := Game.achievements.has(str(def.key))
	var medal := MedalIcon.new()
	medal.setup(str(def.emblem), int(def.tier), unlocked)
	medal.custom_minimum_size = MEDAL
	medal.mouse_filter = Control.MOUSE_FILTER_STOP
	var text := "%s (%s)\n%s · Premio: %d xp y $%d" % [def.name, GameArt.TIER_NAMES[clampi(int(def.tier) - 1, 0, 3)], def.desc,
		int(def.reward.xp), int(def.reward.money)]
	medal.tooltip_text = text
	medal.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_detail.text = ("Conseguido: " if unlocked else "") + text
			_detail.add_theme_color_override("font_color", GameArt.tier_color(int(def.tier)).lightened(0.3) if unlocked else MenuTheme.TEXT))
	return medal
