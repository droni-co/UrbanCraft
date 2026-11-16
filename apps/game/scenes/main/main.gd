extends Control
## Pantalla de título: verifica el backend, exige iniciar sesión y entra al mundo.
##
## Sin sesión no se puede jugar. Con una sesión guardada se puede entrar aunque
## el servidor no responda (se usa el mapa de demostración).
## Para depurar: botón de usuario de prueba (builds de depuración) o
##     godot --path apps/game -- --dev-login=ana
##
## La primera vez que se abre en la sesión hace una intro corta (la ilustración
## se aleja, cae el logo y entra el panel). Un clic o una tecla la salta.
## El arte está en assets/art/ui (ver su README).

const WORLD_SCENE := "res://scenes/world/world.tscn"
const TAGLINE := "Explora tu ciudad. Juega con tus amigos."
## En pantallas más angostas el panel va abajo al centro.
const NARROW_WIDTH := 520.0
const CARD_WIDTH := 204.0
## La ilustración se agranda un poco y se corre a la izquierda para que el
## panel (a la derecha) no tape a los personajes.
const ART_SCALE := 1.08
const ART_SHIFT := Vector2(-19, 0)
const INTRO_SECONDS := 2.6

## La intro solo se ve una vez por ejecución (al volver del mundo no).
static var _intro_played := false

var status_label: Label
var play_button: Button
var retry_button: Button

var _account: AccountSection
var _online := false
var _first_check := true

var _art: TextureRect
var _logo: TextureRect
var _tagline: Label
var _card: PanelContainer
var _footer: Label
var _status_dot: Panel
var _fade: ColorRect
var _motes: CPUParticles2D
var _intro: Tween
var _drift: Tween


func _ready() -> void:
	Online.stop()  # fuera del mundo no se aparece para los demás
	UiArt.smooth(self)
	theme = MenuTheme.build()
	_build()
	resized.connect(_fit)
	_fit()

	play_button.pressed.connect(_play)
	retry_button.pressed.connect(_check_backend)
	Auth.session_changed.connect(func(_user: Dictionary) -> void: _refresh_play())
	_refresh_play()
	_start_intro()
	_check_backend()


func _unhandled_input(event: InputEvent) -> void:
	var skip := (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton \
			or event is InputEventScreenTouch) and event.is_pressed()
	if skip and _intro and _intro.is_running():
		_intro.custom_step(INTRO_SECONDS + 1.0)
		get_viewport().set_input_as_handled()


func _play() -> void:
	if not Auth.is_signed_in():
		return
	play_button.disabled = true
	var out := create_tween()
	out.tween_property(_fade, "color:a", 1.0, 0.35)
	out.tween_callback(func() -> void: get_tree().change_scene_to_file(WORLD_SCENE))


func _refresh_play() -> void:
	var can_play := Auth.is_signed_in()
	play_button.disabled = not can_play
	play_button.tooltip_text = "" if can_play else "Inicia sesión para jugar"
	if can_play and not GameSettings.touch_controls_enabled:
		play_button.grab_focus()


func _check_backend() -> void:
	retry_button.disabled = true
	_set_status("Conectando con el servidor…", MenuTheme.GOLD)
	status_label.tooltip_text = Api.base_url
	var res := await Api.health()
	_online = res.ok
	if _online:
		_set_status("Servidor en línea", MenuTheme.SUCCESS)
		await Auth.wait_startup()
		if Auth.is_signed_in() and not _first_check:
			await Auth.refresh_profile()  # al reintentar: el token pudo caducar
		await _account.refresh_methods()
	elif Auth.is_signed_in():
		_set_status("Sin conexión: se usará el mapa de demostración", MenuTheme.DANGER)
	else:
		_set_status("Sin conexión con el servidor: no se puede iniciar sesión", MenuTheme.DANGER)
	_first_check = false
	retry_button.disabled = false
	retry_button.visible = not _online
	_refresh_play()


func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	var dot := StyleBoxFlat.new()
	dot.bg_color = color
	dot.set_corner_radius_all(4)
	dot.anti_aliasing = true
	_status_dot.add_theme_stylebox_override("panel", dot)


# --- Interfaz -------------------------------------------------------------------

func _build() -> void:
	var sky := ColorRect.new()  # por si la ilustración no llega a cubrir (letterbox)
	sky.color = Color("0d1626")
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_art = TextureRect.new()
	_art.texture = UiArt.screen("title")
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_motes = _make_motes()
	add_child(_motes)

	# Sombra abajo (para leer el pie y el panel) y un toque arriba (para el logo).
	add_child(_gradient([Color(0.04, 0.07, 0.13, 0.0), Color(0.04, 0.07, 0.13, 0.0), Color(0.04, 0.07, 0.13, 0.78)],
		[0.0, 0.55, 1.0]))
	add_child(_gradient([Color(1, 0.93, 0.8, 0.18), Color(1, 0.93, 0.8, 0.0)], [0.0, 0.3]))

	_logo = TextureRect.new()
	_logo.texture = UiArt.LOGO
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)

	_tagline = Label.new()
	_tagline.text = TAGLINE
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tagline.add_theme_font_override("font", UiArt.FONT_BOLD)
	_tagline.add_theme_font_size_override("font_size", 11)
	_tagline.add_theme_color_override("font_color", Color("fff6e4"))
	_tagline.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.05, 0.85))
	_tagline.add_theme_constant_override("outline_size", 4)
	_tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tagline)

	_card = PanelContainer.new()
	_card.theme_type_variation = &"MenuPanel"
	add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_card.add_child(column)

	_account = AccountSection.new()
	_account.compact = true
	column.add_child(_account)

	play_button = Button.new()
	play_button.text = "Jugar"
	play_button.theme_type_variation = &"PrimaryButton"
	play_button.icon = UiArt.icon("play")
	play_button.expand_icon = true
	play_button.add_theme_font_override("font", UiArt.FONT_DISPLAY)
	play_button.add_theme_font_size_override("font_size", 17)
	play_button.add_theme_constant_override("icon_max_width", 18)
	play_button.custom_minimum_size = Vector2(0, 38)
	column.add_child(play_button)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 5)
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(status_row)
	_status_dot = Panel.new()
	_status_dot.custom_minimum_size = Vector2(6, 6)
	_status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_row.add_child(_status_dot)
	status_label = Label.new()
	status_label.theme_type_variation = &"HintLabel"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.mouse_filter = Control.MOUSE_FILTER_PASS
	status_row.add_child(status_label)
	retry_button = Button.new()
	retry_button.text = "Reintentar"
	retry_button.add_theme_font_size_override("font_size", 9)
	retry_button.visible = false
	status_row.add_child(retry_button)

	_footer = Label.new()
	_footer.text = "v%s  ·  Mapa © OpenStreetMap contributors" % ProjectSettings.get_setting("application/config/version", "")
	_footer.add_theme_font_size_override("font_size", 8)
	_footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_footer.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_footer.add_theme_constant_override("outline_size", 3)
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_footer)
	_footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_footer.offset_left = 10
	_footer.offset_top = -18
	_footer.offset_bottom = -6

	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.03, 0.06, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _gradient(colors: Array, offsets: Array) -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 256
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


## Motas de luz cálida que flotan sobre la ciudad (polvo al atardecer).
func _make_motes() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 40
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0.3, -1)
	p.spread = 35.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 0.85, 0.55, 0.0), Color(1, 0.85, 0.55, 0.55), Color(1, 0.9, 0.7, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	p.color_ramp = fade
	var dot := GradientTexture2D.new()
	var soft := Gradient.new()
	soft.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	dot.gradient = soft
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 16
	dot.height = 16
	p.texture = dot
	return p


## Acomoda logo, panel y partículas al tamaño de la pantalla.
func _fit() -> void:
	if _card == null:
		return
	var screen := size
	var narrow := screen.x < NARROW_WIDTH
	var logo_w := minf(screen.x * (0.8 if narrow else 0.5), 340.0)
	var logo_h := logo_w * UiArt.LOGO.get_height() / UiArt.LOGO.get_width()
	var logo_top := 14.0 if not narrow else 22.0
	_logo.size = Vector2(logo_w, logo_h)
	_logo.position = Vector2((screen.x - logo_w) / 2.0, logo_top)
	_logo.pivot_offset = _logo.size / 2.0
	_tagline.size = Vector2(screen.x, 16)
	_tagline.position = Vector2(0, logo_top + logo_h - 2.0)

	_card.custom_minimum_size.x = minf(CARD_WIDTH, screen.x - 24.0)
	_card.size = Vector2(_card.custom_minimum_size.x, 0)
	_card.reset_size()
	var card_size := _card.get_combined_minimum_size()
	if narrow:
		_card.position = Vector2((screen.x - card_size.x) / 2.0, screen.y - card_size.y - 26.0)
	else:
		_card.position = Vector2(screen.x - card_size.x - 14.0, screen.y - card_size.y - 22.0)

	_motes.position = Vector2(screen.x / 2.0, screen.y * 0.75)
	_motes.emission_rect_extents = Vector2(screen.x / 2.0, screen.y * 0.3)
	_art.pivot_offset = screen / 2.0


# --- Intro ------------------------------------------------------------------------

func _start_intro() -> void:
	_art.scale = Vector2(ART_SCALE, ART_SCALE)
	_art.position = ART_SHIFT
	_drift_art()
	_card.modulate.a = 0.0
	_footer.modulate.a = 0.0
	_tagline.modulate.a = 0.0
	_logo.modulate.a = 0.0
	if _intro_played:
		_intro = create_tween().set_parallel()
		_intro.tween_property(_logo, "modulate:a", 1.0, 0.3)
		_intro.tween_property(_tagline, "modulate:a", 1.0, 0.3)
		_intro.tween_property(_card, "modulate:a", 1.0, 0.3)
		_intro.tween_property(_footer, "modulate:a", 1.0, 0.3)
		return
	_intro_played = true
	_fade.color.a = 1.0
	_art.scale = Vector2(1.18, 1.18)
	_logo.scale = Vector2(0.55, 0.55)
	await get_tree().process_frame  # tamaños listos (pivotes)
	_fit()
	var card_x := _card.position.x
	_card.position.x += 40.0

	_intro = create_tween().set_parallel()
	_intro.tween_property(_fade, "color:a", 0.0, 1.2).set_ease(Tween.EASE_OUT)
	_intro.tween_property(_art, "scale", Vector2(ART_SCALE, ART_SCALE), INTRO_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_intro.tween_property(_logo, "modulate:a", 1.0, 0.35).set_delay(0.8)
	_intro.tween_property(_logo, "scale", Vector2.ONE, 0.7).set_delay(0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_intro.tween_property(_tagline, "modulate:a", 1.0, 0.5).set_delay(1.5)
	_intro.tween_property(_card, "modulate:a", 1.0, 0.45).set_delay(1.9)
	_intro.tween_property(_card, "position:x", card_x, 0.55).set_delay(1.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_intro.tween_property(_footer, "modulate:a", 1.0, 0.5).set_delay(2.1)


## Movimiento lento de cámara sobre la ilustración (zoom y paneo suaves).
func _drift_art() -> void:
	_drift = create_tween().set_loops()
	_drift.tween_property(_art, "position", ART_SHIFT + Vector2(-6, -4), 14.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_drift.tween_property(_art, "position", ART_SHIFT + Vector2(6, 3), 14.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# El logo respira apenas.
	var bob := create_tween().set_loops()
	bob.tween_property(_logo, "position:y", 2.0, 2.2).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(_logo, "position:y", -2.0, 2.2).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
