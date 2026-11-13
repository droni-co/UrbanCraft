class_name CharacterSection
extends VBoxContainer
## Sección "Personaje" del menú: elegir la skin del jugador.
##
## Muestra todos los personajes de assets/art/characters/ (CharacterSkins).
## Al tocar uno se ve en grande, caminando y girando; "Usar este personaje" lo
## guarda en la cuenta (servidor) y los demás jugadores lo ven al momento.

const PREVIEW_SIZE := Vector2(64, 96)
const CARD_SIZE := Vector2(64, 74)
## Segundos que la vista previa mira hacia cada dirección.
const TURN_SECONDS := 1.2
## Orden de giro de la vista previa: de frente y luego en sentido horario.
const TURN_ROWS := [2, 3, 4, 5, 6, 7, 0, 1]

var _selected := ""
var _busy := false
var _anim_time := 0.0
var _preview: TextureRect
var _preview_frame := AtlasTexture.new()
var _name_label: Label
var _current_label: Label
var _use_button: Button
var _message: Label
var _cards_box: HFlowContainer
var _cards := {}  # id -> Button
var _group := ButtonGroup.new()


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	if theme == null:
		theme = MenuTheme.build()

	var title := Label.new()
	title.text = "Personaje"
	title.theme_type_variation = &"SectionTitle"
	add_child(title)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	add_child(top)

	var frame_panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.25)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(4)
	frame_panel.add_theme_stylebox_override("panel", style)
	top.add_child(frame_panel)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = PREVIEW_SIZE
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.texture = _preview_frame
	frame_panel.add_child(_preview)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 4)
	top.add_child(info)
	_name_label = Label.new()
	_name_label.theme_type_variation = &"SectionTitle"
	info.add_child(_name_label)
	_current_label = Label.new()
	_current_label.theme_type_variation = &"HintLabel"
	info.add_child(_current_label)
	_use_button = Button.new()
	_use_button.text = "Usar este personaje"
	_use_button.theme_type_variation = &"PrimaryButton"
	_use_button.custom_minimum_size.y = 24
	_use_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_use_button.pressed.connect(_apply)
	info.add_child(_use_button)
	_message = Label.new()
	_message.theme_type_variation = &"HintLabel"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_message)

	_cards_box = HFlowContainer.new()
	_cards_box.add_theme_constant_override("h_separation", 6)
	_cards_box.add_theme_constant_override("v_separation", 6)
	add_child(_cards_box)
	_build_cards()

	Auth.session_changed.connect(func(_user: Dictionary) -> void: _refresh())
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_select(_current(), false))
	_select(_current(), false)


func focus_first() -> void:
	var card: Button = _cards.get(_selected)
	if card:
		card.grab_focus()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _selected.is_empty():
		return
	_anim_time += delta
	var row: int = TURN_ROWS[int(_anim_time / TURN_SECONDS) % TURN_ROWS.size()]
	var col := 1 + int(_anim_time * CharacterSkins.WALK_FPS) % CharacterSkins.WALK_FRAMES
	_preview_frame.region = Rect2(Vector2(col, row) * Vector2(CharacterSkins.FRAME_SIZE), CharacterSkins.FRAME_SIZE)


# --- Interno ----------------------------------------------------------------------

func _build_cards() -> void:
	for id in CharacterSkins.list():
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = _group
		card.theme_type_variation = &"CardButton"
		card.custom_minimum_size = CARD_SIZE
		card.icon = CharacterSkins.frame(CharacterSkins.sheet_texture(id), 0, 2)
		card.expand_icon = true
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		card.texture_filter = CharacterSkins.filter_for(id)
		card.text = CharacterSkins.display_name(id)
		card.tooltip_text = CharacterSkins.display_name(id)
		card.pressed.connect(_select.bind(id, true))
		_cards_box.add_child(card)
		_cards[id] = card
	if _cards.is_empty():
		_message.text = "No hay personajes en assets/art/characters/."


## Personaje actual de la cuenta.
func _current() -> String:
	return CharacterSkins.resolve(Auth.user.get("skin"))


func _select(id: String, from_click: bool) -> void:
	if id.is_empty():
		return
	if id != _selected:
		_anim_time = 0.0
		if from_click:
			_message.text = ""
	_selected = id
	_preview_frame.atlas = CharacterSkins.sheet_texture(id)
	_preview.texture_filter = CharacterSkins.filter_for(id)
	_preview_frame.region = Rect2(Vector2(0, 2) * Vector2(CharacterSkins.FRAME_SIZE), CharacterSkins.FRAME_SIZE)
	_refresh()


func _refresh() -> void:
	var current := _current()
	for id: String in _cards:
		var card: Button = _cards[id]
		card.set_pressed_no_signal(id == _selected)
		# El personaje actual, con el nombre en verde en todos los estados.
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			if id == current:
				card.add_theme_color_override(state, MenuTheme.SUCCESS)
			else:
				card.remove_theme_color_override(state)
	_name_label.text = CharacterSkins.display_name(_selected)
	_current_label.text = "Es tu personaje actual." if _selected == current else "Así te verán los demás jugadores."
	_use_button.visible = _selected != current
	_use_button.disabled = _busy or not Auth.is_signed_in()


func _apply() -> void:
	if _busy or _selected.is_empty():
		return
	_busy = true
	_message.text = "Guardando…"
	_message.remove_theme_color_override("font_color")
	_refresh()
	var result := await Auth.update_skin(_selected)
	_busy = false
	_message.text = result.message
	_message.add_theme_color_override("font_color", MenuTheme.SUCCESS if result.ok else MenuTheme.DANGER)
	_refresh()
