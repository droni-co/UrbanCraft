extends Node
## Voz con amigos. Autoload "Voice". Ver docs/voz.md.
##
## Al activarla oyes a tus amigos en línea que también la tengan activa, y
## ellos a ti. El audio va DIRECTO entre jugadores (WebRTC); el servidor solo
## avisa quién está en la voz y reenvía la señalización (Online.voice_peer,
## Online.rtc_received). Cada pareja se conecta por separado; ofrece el de id
## menor.
##
## Micrófono: pulsar para hablar (acción voice_talk: tecla V o el botón táctil)
## o micrófono abierto (GameSettings.voice_open_mic).
##
## Por ahora solo en la versión web: el navegador hace el WebRTC, el códec
## (Opus) y la cancelación de eco, en web/voice.js. En PC y Android hace falta
## una extensión nativa (fase 2), así que supported() es false.

## Cambió el estado: activada, amigos en la voz o su conexión.
signal changed
## Un amigo empezó o dejó de hablar.
signal speaking_changed(player_id: int, speaking: bool)
## Tu micrófono empezó o dejó de transmitir.
signal transmitting_changed(on: bool)
## Aviso para mostrar en pantalla.
signal notice(text: String)

const JS_PATH := "res://web/voice.js"

## true mientras la voz está activada (aunque aún no haya amigos conectados).
var enabled := false
## Pidiendo permiso para el micrófono.
var starting := false
var transmitting := false
## id -> { nickname, state: "connecting" | "connected" | "failed", speaking, muted }
var peers := {}

var _js: JavaScriptObject
var _js_callback: JavaScriptObject
var _talking := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Online.voice_peer.connect(_on_voice_peer)
	Online.rtc_received.connect(_on_rtc)
	Online.status_changed.connect(_on_status)
	GameSettings.online_settings_changed.connect(_on_settings)
	Auth.session_changed.connect(func(user: Dictionary) -> void:
		if user.is_empty():
			disable())


## La voz funciona en esta plataforma (por ahora, navegadores con WebRTC).
func supported() -> bool:
	return _bridge() != null


## Por qué no se puede activar ahora ("" si se puede).
func unavailable_reason() -> String:
	if not supported():
		return "La voz por ahora solo funciona en la versión web (urbancraft.droni.vip/play)."
	if not Online.is_online():
		return "Sin conexión con el servidor."
	if not GameSettings.online_visible:
		return "En modo fantasma no puedes usar la voz."
	return ""


func toggle() -> void:
	if enabled or starting:
		disable()
	else:
		enable()


## Pide el micrófono y entra a la voz.
func enable() -> void:
	if enabled or starting:
		return
	var reason := unavailable_reason()
	if reason != "":
		notice.emit(reason)
		return
	starting = true
	changed.emit()
	_bridge().start(JSON.stringify(Online.ice_servers))  # responde con el evento "mic"


func disable() -> void:
	if not enabled and not starting:
		return
	if enabled:
		Online.send_voice(false)
	enabled = false
	starting = false
	peers.clear()
	if _js:
		_js.stop()
	_set_transmitting(false)
	changed.emit()


func set_muted(player_id: int, muted: bool) -> void:
	if not peers.has(player_id):
		return
	peers[player_id].muted = muted
	if muted:
		peers[player_id].speaking = false
	if _js:
		_js.setMuted(player_id, muted)
	changed.emit()


## Amigos conectados (estado "connected").
func connected_count() -> int:
	var n := 0
	for p: Dictionary in peers.values():
		if p.state == "connected":
			n += 1
	return n


# --- Pulsar para hablar -----------------------------------------------------------

func _process(_delta: float) -> void:
	if not enabled:
		return
	# Escribiendo en el chat, la V es una letra.
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is LineEdit or focus is TextEdit
	var talking := Input.is_action_pressed("voice_talk") and not typing and not GameSettings.voice_open_mic
	if talking != _talking:
		_talking = talking
		_js.setTalking(talking)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _talking and _js:
		_talking = false
		_js.setTalking(false)


# --- Servidor ---------------------------------------------------------------------

func _on_voice_peer(player_id: int, nickname: String, on: bool) -> void:
	if not enabled:
		return
	if player_id == Online.my_id:
		if not on:  # el servidor no nos dejó entrar (modo fantasma)
			disable()
			notice.emit("En modo fantasma no puedes usar la voz.")
		return
	if on:
		if not peers.has(player_id):
			peers[player_id] = {"nickname": nickname, "state": "connecting", "speaking": false, "muted": false}
			_js.addPeer(player_id, Online.my_id < player_id)
			notice.emit("%s está en la voz." % nickname)
	elif peers.has(player_id):
		peers.erase(player_id)
		_js.removePeer(player_id)
		notice.emit("%s salió de la voz." % nickname)
	changed.emit()


func _on_rtc(from_id: int, kind: String, data: String) -> void:
	if enabled and _js:
		_js.receive(from_id, kind, data)


func _on_status(status: String) -> void:
	if not enabled:
		return
	if status == "online":
		Online.send_voice(true)  # reconectado: volver a entrar
	elif not Online.is_active():
		disable()  # salió del mundo
	else:
		# Se cortó el servidor: las conexiones directas siguen, pero ya no
		# llegarán avisos de entrada o salida; se rehacen al reconectar.
		peers.clear()
		if _js:
			_js.removeAll()
		changed.emit()


func _on_settings() -> void:
	if (enabled or starting) and not GameSettings.online_visible:
		disable()
		notice.emit("Modo fantasma: se desactivó la voz.")
	if _js:
		_js.setOpenMic(GameSettings.voice_open_mic)


# --- Puente con web/voice.js --------------------------------------------------------

func _bridge() -> JavaScriptObject:
	if _js or not OS.has_feature("web"):
		return _js
	var code := FileAccess.get_file_as_string(JS_PATH)
	if code.is_empty():
		push_warning("Voz: falta %s en el export web (include_filter)." % JS_PATH)
		return null
	JavaScriptBridge.eval(code, true)
	var api: JavaScriptObject = JavaScriptBridge.get_interface("UCVoice")
	if api == null or not api.supported():
		return null
	_js = api
	_js_callback = JavaScriptBridge.create_callback(_on_js_event)
	_js.setHandler(_js_callback)
	_js.setOpenMic(GameSettings.voice_open_mic)
	return _js


func _on_js_event(args: Array) -> void:
	var event: Variant = JSON.parse_string(str(args[0])) if not args.is_empty() else null
	if not (event is Dictionary):
		return
	match str(event.get("e")):
		"mic":
			_on_mic(bool(event.get("ok")), str(event.get("error", "")))
		"signal":
			Online.send_rtc(int(event.to), str(event.k), str(event.d))
		"state":
			_on_peer_state(int(event.id), str(event.s))
		"speaking":
			var id := int(event.id)
			if peers.has(id):
				peers[id].speaking = bool(event.on)
				speaking_changed.emit(id, peers[id].speaking)
		"tx":
			_set_transmitting(bool(event.on))


func _on_mic(ok: bool, error: String) -> void:
	if not starting:
		if ok and _js:
			_js.stop()  # se desactivó mientras pedía permiso
		return
	starting = false
	if not ok:
		var message := "No se pudo usar el micrófono."
		match error:
			"NotAllowedError", "SecurityError":
				message = "Permiso de micrófono denegado: actívalo en el navegador (icono junto a la dirección)."
			"NotFoundError":
				message = "No se encontró ningún micrófono."
			"NotReadableError":
				message = "Otra aplicación está usando el micrófono."
		notice.emit(message)
		changed.emit()
		return
	enabled = true
	Online.send_voice(true)
	notice.emit("Voz activada: mantén V para hablar." if not GameSettings.voice_open_mic else "Voz activada (micrófono abierto).")
	changed.emit()


func _on_peer_state(player_id: int, state: String) -> void:
	if not peers.has(player_id):
		return
	var previous: String = peers[player_id].state
	match state:
		"connected":
			peers[player_id].state = "connected"
		"failed":
			peers[player_id].state = "failed"
			if previous != "failed":
				notice.emit("No se pudo conectar la voz con %s (su red no lo permite)." % peers[player_id].nickname)
		"disconnected", "connecting", "new":
			peers[player_id].state = "connecting"
		_:
			return
	changed.emit()


func _set_transmitting(on: bool) -> void:
	if on != transmitting:
		transmitting = on
		transmitting_changed.emit(on)
