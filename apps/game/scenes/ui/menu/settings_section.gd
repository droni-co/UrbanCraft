class_name SettingsSection
extends VBoxContainer
## Sección "Ajustes" del menú: volumen de la música y de los efectos, por
## separado. Se guardan en el dispositivo (GameSettings).

var _music_value: Label
var _sfx_value: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	if theme == null:
		theme = MenuTheme.build()

	var title := Label.new()
	title.text = "Sonido"
	title.theme_type_variation = &"SectionTitle"
	add_child(title)

	_music_value = _slider_row("Música", GameSettings.music_volume, func(value: float) -> void:
		GameSettings.music_volume = value
		_refresh())
	var sfx_slider := Array()
	_sfx_value = _slider_row("Efectos", GameSettings.sfx_volume, func(value: float) -> void:
		GameSettings.sfx_volume = value
		_refresh(), sfx_slider)
	# Al soltar el control de efectos suena uno, para oír cómo queda.
	(sfx_slider[0] as HSlider).drag_ended.connect(func(_changed: bool) -> void: GameAudio.play("ring"))

	var hint := Label.new()
	hint.text = "Los efectos incluyen el ambiente de la ciudad (pájaros, grillos, agua). " \
		+ "La voz con amigos no cambia con estos controles."
	hint.theme_type_variation = &"HintLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	_refresh()


## Fila "Nombre  [—————o——]  80 %". Devuelve la etiqueta del porcentaje.
func _slider_row(text: String, value: float, on_change: Callable, out: Array = []) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 52
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 24  # cómodo para el dedo
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	out.append(slider)

	var percent := Label.new()
	percent.custom_minimum_size.x = 34
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(percent)
	return percent


func _refresh() -> void:
	_music_value.text = _percent(GameSettings.music_volume)
	_sfx_value.text = _percent(GameSettings.sfx_volume)


func _percent(value: float) -> String:
	return "Sin sonido" if value <= 0.001 else "%d %%" % roundi(value * 100.0)
