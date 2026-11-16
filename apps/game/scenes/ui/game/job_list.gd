class_name JobList
extends RefCounted
## Lista de encargos (ofrecidos y en curso) para la ventana de un lugar y para
## Menú → Misiones. `run` recibe la acción a ejecutar (un Callable que devuelve
## el resultado de Game) y se encarga de refrescar la vista.


static func fill(list: VBoxContainer, run: Callable) -> void:
	var active := Game.jobs.filter(func(j: Dictionary) -> bool: return j.get("status") == "active")
	var offered := Game.jobs.filter(func(j: Dictionary) -> bool: return j.get("status") == "offered")

	if not active.is_empty():
		_title(list, "En curso (%d)" % active.size())
		for job: Dictionary in active:
			_card(list, job, run)
	_title(list, "Disponibles")
	if offered.is_empty():
		GameWindow.hint(list, "No hay encargos por ahora. Acércate a una zona con más lugares.")
	for job: Dictionary in offered:
		_card(list, job, run)
	var footer := HBoxContainer.new()
	list.add_child(footer)
	GameWindow.small_button(footer, "Pedir otros encargos", func() -> void:
		run.call(func() -> Dictionary: return await Game.new_jobs()))


static func _title(list: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiArt.FONT_BOLD)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", MenuTheme.GOLD)
	list.add_child(label)


static func _card(list: VBoxContainer, job: Dictionary, run: Callable) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.22)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(5)
	panel.add_theme_stylebox_override("panel", style)
	list.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	panel.add_child(column)

	var reward: Dictionary = job.get("reward", {})
	var icon := "domicilio"
	match job.get("kind"):
		"errand":
			icon = "bolsa"
		"tour":
			icon = "mapa"
	var head := GameWindow.row(GameArt.medal(icon), str(job.title),
		"$%d · %d xp" % [int(reward.get("money", 0)), int(reward.get("xp", 0))], Color("ffe08a"))
	column.add_child(head)
	var id := int(job.id)
	if job.get("status") == "offered":
		GameWindow.small_button(head, "Aceptar", func() -> void:
			run.call(func() -> Dictionary: return await Game.accept_job(id)), &"PrimaryButton")
	else:
		GameWindow.small_button(head, "Dejar", func() -> void:
			run.call(func() -> Dictionary: return await Game.abandon_job(id)))

	var text := Label.new()
	text.text = str(job.text)
	text.theme_type_variation = &"HintLabel"
	text.add_theme_font_size_override("font_size", 8)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(text)
	if job.get("status") == "active":
		for step: Dictionary in job.get("steps", []):
			var line := Label.new()
			line.text = "%s%s" % ["Listo: " if step.get("done", false) else "• ", step_text(step)]
			line.add_theme_font_size_override("font_size", 8)
			line.add_theme_color_override("font_color", MenuTheme.SUCCESS if step.get("done", false) else MenuTheme.TEXT)
			column.add_child(line)


## "Recoge en Panadería X", "Lleva 2 × Pan a Y"…
static func step_text(step: Dictionary) -> String:
	var place := str(step.get("poi", {}).get("name", ""))
	match step.get("type"):
		"pickup":
			return "Recoge el paquete en %s" % place
		"deliver":
			return "Entrega el paquete en %s" % place
		"bring":
			var key := str(step.get("item", ""))
			return "Lleva %d × %s a %s (tienes %d)" % [int(step.get("qty", 1)), Game.item_name(key), place, Game.count(key)]
	return "Pasa por %s" % place
