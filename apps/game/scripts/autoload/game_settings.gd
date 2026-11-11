extends Node
## Ajustes globales de plataforma. Autoload "GameSettings".
##
## Los controles táctiles se activan en móvil, en pantallas táctiles o
## forzándolos para probar en PC con:  godot --path apps/game -- --touch
## (o el ajuste de proyecto urbancraft/debug/force_touch_controls).

signal touch_controls_changed(enabled: bool)

const SETTING_FORCE_TOUCH := "urbancraft/debug/force_touch_controls"

var touch_controls_enabled := false:
	set(value):
		touch_controls_enabled = value
		touch_controls_changed.emit(value)


func _ready() -> void:
	var forced: bool = "--touch" in OS.get_cmdline_user_args() \
		or ProjectSettings.get_setting(SETTING_FORCE_TOUCH, false)
	var is_mobile := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")

	touch_controls_enabled = forced or is_mobile or DisplayServer.is_touchscreen_available()

	# En PC, con controles táctiles forzados, el ratón simula toques.
	if forced and not is_mobile:
		Input.emulate_touch_from_mouse = true
