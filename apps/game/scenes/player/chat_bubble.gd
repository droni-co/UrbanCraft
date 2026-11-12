class_name ChatBubble
extends Node2D
## Globo con un mensaje de chat sobre la cabeza de un personaje (jugador o
## remoto). Se queda unos segundos según el largo del texto y se desvanece.
## El texto se parte en líneas a mano (sin autowrap) para que el tamaño se
## conozca al momento y el globo quede centrado y pegado a la cabeza.

const FONT_SIZE := 8
const MAX_WIDTH := 120.0
const MAX_LINES := 3
const PADDING := Vector2(4, 2)

var _panel: PanelContainer
var _label: Label
var _tween: Tween


func _ready() -> void:
	z_index = 100  # por encima de edificios y otros personajes
	z_as_relative = false
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.92)
	box.set_corner_radius_all(4)
	box.content_margin_left = PADDING.x
	box.content_margin_right = PADDING.x
	box.content_margin_top = PADDING.y
	box.content_margin_bottom = PADDING.y
	box.anti_aliasing = true
	_panel.add_theme_stylebox_override("panel", box)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", Color(0.1, 0.12, 0.16))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	add_child(_panel)
	modulate.a = 0.0


## Muestra `text`; el borde inferior del globo queda en y = 0 (la cabeza).
func say(text: String) -> void:
	var font := _label.get_theme_font("font")
	_label.text = "\n".join(wrap_text(text, font, FONT_SIZE, MAX_WIDTH, MAX_LINES))
	_panel.reset_size()
	var size := _panel.get_combined_minimum_size()
	_panel.size = size
	_panel.position = Vector2(-size.x / 2.0, -size.y)

	if _tween:
		_tween.kill()
	var stay := clampf(2.5 + text.length() * 0.06, 3.0, 8.0)
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.12)
	_tween.tween_interval(stay)
	_tween.tween_property(self, "modulate:a", 0.0, 0.5)


## Parte el texto en líneas de hasta `max_width` píxeles (palabras largas se
## cortan), con "…" si no cabe en `max_lines`.
static func wrap_text(text: String, font: Font, font_size: int, max_width: float, max_lines: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		var candidate := word if line.is_empty() else line + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			line = candidate
			continue
		if not line.is_empty():
			lines.append(line)
		line = word
		# Palabra más ancha que el globo: se corta por caracteres.
		while font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width and line.length() > 1:
			var cut := line.length() - 1
			while cut > 1 and font.get_string_size(line.substr(0, cut), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
				cut -= 1
			lines.append(line.substr(0, cut))
			line = line.substr(cut)
	if not line.is_empty():
		lines.append(line)
	if lines.size() > max_lines:
		lines.resize(max_lines)
		lines[max_lines - 1] = lines[max_lines - 1].left(maxi(lines[max_lines - 1].length() - 1, 0)) + "…"
	return lines
