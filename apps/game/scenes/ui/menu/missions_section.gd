class_name MissionsSection
extends VBoxContainer
## Menú → Misiones: el capítulo de la historia (metas, pista, llamar al
## personaje si no hay dónde encontrarlo) y los encargos.

var _story: VBoxContainer
var _jobs: VBoxContainer
var _status: Label
var _busy := false


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_story = VBoxContainer.new()
	_story.add_theme_constant_override("separation", 2)
	add_child(_story)
	add_child(HSeparator.new())
	var title := Label.new()
	title.text = "Encargos"
	title.theme_type_variation = &"SectionTitle"
	add_child(title)
	GameWindow.hint(self, "Trabajos cortos con los lugares que tienes cerca. Puedes llevar 3 a la vez; se cumplen entrando a cada lugar.")
	_status = Label.new()
	_status.theme_type_variation = &"HintLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	add_child(_status)
	_jobs = VBoxContainer.new()
	_jobs.add_theme_constant_override("separation", 3)
	add_child(_jobs)
	Game.changed.connect(_refresh)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_status.visible = false
			_refresh()
			Game.refresh_jobs())
	_refresh()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	GameWindow.clear(_story)
	var chapter: Variant = Game.story.get("chapter")
	var title := Label.new()
	title.theme_type_variation = &"SectionTitle"
	_story.add_child(title)
	if chapter is Dictionary:
		var npc := Game.npc(str(chapter.npc))
		title.text = "Capítulo %d de %d: %s" % [int(Game.story.index) + 1, int(Game.story.total), chapter.title]
		var who := GameWindow.row(GameArt.portrait(str(npc.portrait)), "%s — %s" % [npc.name, chapter.summary], "", MenuTheme.TEXT_DIM, true)
		who.get_child(0).custom_minimum_size = Vector2(28, 28)
		who.get_child(1).add_theme_font_size_override("font_size", 9)
		_story.add_child(who)
		for goal: Dictionary in Game.story.get("goals", []):
			var done: bool = goal.get("done", false)
			var count := int(goal.get("count", 1))
			var row := GameWindow.row(null, ("Listo: " if done else "• ") + str(goal.text),
				"%s / %s" % [PlayerStats.format_number(goal.progress), PlayerStats.format_number(count)] if count > 1 else "",
				MenuTheme.SUCCESS if done else MenuTheme.TEXT_DIM, true)
			row.get_child(0).add_theme_color_override("font_color", MenuTheme.SUCCESS if done else MenuTheme.TEXT)
			_story.add_child(row)
		if not str(Game.story.get("hint", "")).is_empty():
			GameWindow.hint(_story, str(Game.story.hint))
		var talk := Game.talk_goal()
		if not talk.is_empty():
			var row := HBoxContainer.new()
			_story.add_child(row)
			GameWindow.small_button(row, "No hay un lugar así cerca: llamar a %s" % Game.npc(str(talk.npc)).name, _call_npc)
	else:
		title.text = "Historia completa"
		GameWindow.hint(_story, str(Game.story.get("hint", "Terminaste la historia.")))

	GameWindow.clear(_jobs)
	JobList.fill(_jobs, _run)


func _call_npc() -> void:
	_run(func() -> Dictionary: return await Game.story_talk())


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
	_refresh()
