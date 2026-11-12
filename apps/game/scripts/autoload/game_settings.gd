extends Node
## Ajustes globales de plataforma. Autoload "GameSettings".
##
## Los controles táctiles se activan en móvil, en pantallas táctiles o
## forzándolos para probar en PC con:  godot --path apps/game -- --touch
## (o el ajuste de proyecto urbancraft/debug/force_touch_controls).

signal touch_controls_changed(enabled: bool)
## Se emite al cambiar cualquier preferencia del minimapa o la brújula.
signal minimap_settings_changed
## Se emite al cambiar cualquier preferencia de las etiquetas del mapa.
signal labels_settings_changed
## Cambió la visibilidad del panel de stats (hambre, xp, dinero) bajo el menú.
signal stats_settings_changed
## Cambió si los demás jugadores te ven (multijugador).
signal online_settings_changed

enum ScreenCorner { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

const SETTING_FORCE_TOUCH := "urbancraft/debug/force_touch_controls"

var touch_controls_enabled := false:
	set(value):
		touch_controls_enabled = value
		touch_controls_changed.emit(value)


# --- Minimapa (preferencias del usuario; más adelante se editarán y persistirán) ---

var minimap_visible := true:
	set(value):
		minimap_visible = value
		minimap_settings_changed.emit()

## Esquina de la pantalla donde se muestra el minimapa.
var minimap_corner := ScreenCorner.TOP_LEFT:
	set(value):
		minimap_corner = value
		minimap_settings_changed.emit()

## Tamaño en píxeles de la resolución base (640x360). Más ancho que alto porque
## la vista isométrica es 2:1.
var minimap_size := Vector2(128, 80):
	set(value):
		minimap_size = value
		minimap_settings_changed.emit()

## Separación con los bordes: x = lateral, y = vertical (deja libre la barra superior).
var minimap_margin := Vector2(8, 24):
	set(value):
		minimap_margin = value
		minimap_settings_changed.emit()

## 1.0 = muestra toda la zona de juego; >1 acerca.
var minimap_zoom := 1.0:
	set(value):
		minimap_zoom = clampf(value, 0.5, 8.0)
		minimap_settings_changed.emit()

## Radio (metros) que muestra el minimapa con zoom 1. También define cuánto
## mapa alrededor del jugador se mantiene cargado como datos.
var minimap_view_radius_meters := 400.0:
	set(value):
		minimap_view_radius_meters = clampf(value, 100.0, 2000.0)
		minimap_settings_changed.emit()

## true = el minimapa sigue al jugador; false = queda centrado en tu ubicación real.
var minimap_follow_player := true:
	set(value):
		minimap_follow_player = value
		minimap_settings_changed.emit()

var compass_visible := true:
	set(value):
		compass_visible = value
		minimap_settings_changed.emit()


## Información de depuración (chunk, FPS) en la barra superior.
var debug_info_visible := OS.is_debug_build()


# --- Etiquetas del mapa (nombres de calles, lugares y portales) -------------------

## Nombres de calles pintados sobre el asfalto.
var street_names_visible := true:
	set(value):
		street_names_visible = value
		labels_settings_changed.emit()

## Nombres de parques, plazas, edificios y puntos de interés cercanos.
var place_names_visible := true:
	set(value):
		place_names_visible = value
		labels_settings_changed.emit()

## Números de portal de las casas junto al jugador.
var house_numbers_visible := true:
	set(value):
		house_numbers_visible = value
		labels_settings_changed.emit()

## Nombre de la calle actual junto al minimapa.
var current_street_visible := true:
	set(value):
		current_street_visible = value
		labels_settings_changed.emit()

## Multiplicador de opacidad de todas las etiquetas del mundo (0..1).
var labels_opacity := 1.0:
	set(value):
		labels_opacity = clampf(value, 0.0, 1.0)
		labels_settings_changed.emit()


# --- Stats del jugador (HUD) ------------------------------------------------------

## Panel compacto de stats bajo el botón de menú.
var stats_hud_visible := true:
	set(value):
		stats_hud_visible = value
		stats_settings_changed.emit()


# --- Multijugador -----------------------------------------------------------------

## false = modo fantasma: sigues viendo a los demás, pero ellos no te ven.
var online_visible := true:
	set(value):
		online_visible = value
		online_settings_changed.emit()

## Voz con amigos: false = pulsar para hablar (V o botón), true = micrófono
## abierto (transmite cuando detecta voz).
var voice_open_mic := false:
	set(value):
		voice_open_mic = value
		online_settings_changed.emit()


func _ready() -> void:
	var forced: bool = "--touch" in OS.get_cmdline_user_args() \
		or ProjectSettings.get_setting(SETTING_FORCE_TOUCH, false)
	var is_mobile := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")

	touch_controls_enabled = forced or is_mobile or DisplayServer.is_touchscreen_available()

	# En PC, con controles táctiles forzados, el ratón simula toques.
	if forced and not is_mobile:
		Input.emulate_touch_from_mouse = true
