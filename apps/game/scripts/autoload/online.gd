extends Node
## Conexión del multijugador (WebSocket con el backend). Autoload "Online".
##
## El mundo llama start() al entrar (solo con el mapa real) y stop() al salir.
## Mientras tanto:
##   - send_state(): manda tu posición (celdas GLOBALES, float de 64 bits) unas
##     10 veces por segundo mientras te mueves, y al cambiar estando quieto.
##   - players: los jugadores cercanos que ves en pantalla (snapshots ~10/s).
##   - radar: los demás dentro del radio de alcance, con la posición redondeada
##     por privacidad (para los puntos del minimapa).
## Protocolo: apps/backend/app/realtime/protocol.ts. Ver docs/multijugador.md.
##
## Sin conexión se reintenta solo (1 s, 2 s, 4 s… hasta 15 s).

## "offline" | "connecting" | "online"
signal status_changed(status: String)
## Llegó un snapshot: `players` ya está actualizado.
signal players_updated
## Llegó el radar: `radar` ya está actualizado.
signal radar_updated
## Llegó (o cambió) el apodo, nivel o personaje de estos jugadores.
signal info_updated(player_ids: Array)
## Otro jugador hizo una acción visible ("interact", "wave").
signal action_received(player_id: int, kind: String)

const WS_PATH := "/ws"
const MOVE_SEND_INTERVAL := 0.1
const IDLE_SEND_INTERVAL := 5.0
const PING_INTERVAL := 10.0
const MAX_BACKOFF := 15.0

var status := "offline"
## Tu id de usuario en el servidor (0 sin conexión).
var my_id := 0
## id -> { x: float, y: float, d: int, m: int, t: float (segundos al recibirlo) }
var players := {}
## id -> { n: nickname, lv: nivel, s: personaje (skin) o null }
var infos := {}
## Posiciones aproximadas: Array de PackedFloat64Array([x, y]) en celdas globales.
var radar: Array = []
## Radio (celdas) de "cercanos" y radio del radar (metros), según el servidor.
var nearby_radius := 40.0
var radar_radius_meters := 1000.0

var _socket: WebSocketPeer
var _active := false
var _backoff := 1.0
var _retry_at := 0.0
var _last_send := -100.0
var _last_ping := 0.0
var _last_sent := []  # [x, y, d, m] del último estado enviado
var _need_spawn := true
var _spawn_not_before := 0.0


func _ready() -> void:
	# Sigue recibiendo con el menú abierto (pausa); el mundo no envía en pausa.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Auth.session_changed.connect(func(user: Dictionary) -> void:
		if user.is_empty():
			stop())
	GameSettings.online_settings_changed.connect(_send_visibility)


## Empieza (o sigue) conectado. La próxima posición se envía como aparición
## (spawn): el servidor acepta el salto (entrar al mundo, teletransporte).
func start() -> void:
	_active = true
	_need_spawn = true
	if status == "offline":
		_connect()


func stop() -> void:
	_active = false
	if _socket:
		_socket.close(1000, "bye")
	_socket = null
	_set_status("offline")
	_clear()


func is_online() -> bool:
	return status == "online"


## Tu estado en celdas globales con decimales. `dir`: Player.facing_index();
## `move`: 0 quieto, 1 camina, 2 corre. Se llama cada frame: aquí se limita.
func send_state(x: float, y: float, dir: int, move: int) -> void:
	if not is_online():
		return
	var now := _now()
	if _need_spawn and now < _spawn_not_before:
		return
	var changed: bool = _last_sent.is_empty() or _last_sent[2] != dir or _last_sent[3] != move \
		or absf(_last_sent[0] - x) > 0.01 or absf(_last_sent[1] - y) > 0.01
	var interval := MOVE_SEND_INTERVAL if changed else IDLE_SEND_INTERVAL
	if now - _last_send < interval and not _need_spawn:
		return
	var msg := {"t": "state", "x": x, "y": y, "d": dir, "m": move}
	if _need_spawn:
		msg.spawn = true
		_need_spawn = false
	_send(msg)
	_last_send = now
	_last_sent = [x, y, dir, move]


## Acción visible para los jugadores cercanos: "interact" o "wave".
func send_action(kind: String) -> void:
	if is_online():
		_send({"t": "act", "k": kind})


func nickname(player_id: int) -> String:
	return str(infos.get(player_id, {}).get("n", "Jugador"))


func level(player_id: int) -> int:
	return int(infos.get(player_id, {}).get("lv", 1))


## Personaje del jugador (null = el por defecto).
func skin(player_id: int) -> Variant:
	return infos.get(player_id, {}).get("s")


## Cuántos otros jugadores hay en tu radio de alcance (cercanos + radar).
func others_in_range() -> int:
	return players.size() + radar.size()


# --- Conexión ---------------------------------------------------------------------

func _connect() -> void:
	if not Auth.is_signed_in():
		return
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = 256 * 1024
	var url := Api.base_url.replace("https://", "wss://").replace("http://", "ws://") + WS_PATH
	var err := _socket.connect_to_url(url)
	if err != OK:
		_socket = null
		_schedule_retry()
		return
	_set_status("connecting")


func _process(_delta: float) -> void:
	if not _active:
		return
	if _socket == null:
		if status == "offline" and _now() >= _retry_at:
			_connect()
		return

	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if status == "connecting" and _last_ping == 0.0:
				_last_ping = _now()
				_send({"t": "auth", "token": Api.token})
			while _socket.get_available_packet_count() > 0:
				_handle(_socket.get_packet().get_string_from_utf8())
			if is_online() and _now() - _last_ping > PING_INTERVAL:
				_last_ping = _now()
				_send({"t": "ping", "c": Time.get_ticks_msec()})
		WebSocketPeer.STATE_CLOSED:
			var code := _socket.get_close_code()
			_socket = null
			_clear()
			_set_status("offline")
			match code:
				4003:  # token inválido: la sesión caducó
					Auth.refresh_profile()
				4001:  # otra ventana entró con la misma cuenta
					push_warning("Multijugador: la cuenta se conectó desde otro lugar.")
			_schedule_retry()


func _schedule_retry() -> void:
	_retry_at = _now() + _backoff
	_backoff = minf(_backoff * 2.0, MAX_BACKOFF)


# --- Mensajes ---------------------------------------------------------------------

func _handle(raw: String) -> void:
	var msg: Variant = JSON.parse_string(raw)
	if not (msg is Dictionary):
		return
	match msg.get("t"):
		"welcome":
			my_id = int(msg.id)
			nearby_radius = float(msg.get("nearbyRadius", nearby_radius))
			radar_radius_meters = float(msg.get("radarRadiusMeters", radar_radius_meters))
			_backoff = 1.0
			_need_spawn = true
			_last_sent = []
			_set_status("online")
			_send_visibility()
		"snap":
			_on_snap(msg)
		"radar":
			radar.clear()
			for p: Array in msg.get("p", []):
				radar.append(PackedFloat64Array([float(p[0]), float(p[1])]))
			radar_updated.emit()
		"act":
			action_received.emit(int(msg.id), str(msg.k))
		"reject":
			# Salto rechazado (velocidad o teletransporte muy seguido):
			# se reintenta como aparición cuando el servidor lo permita.
			_need_spawn = true
			_spawn_not_before = _now() + float(msg.get("retry", 1000)) / 1000.0
		"error":
			push_warning("Multijugador: %s" % msg.get("e"))


func _on_snap(msg: Dictionary) -> void:
	var info: Variant = msg.get("info")
	var changed := []
	if info is Dictionary:
		for id: String in info:
			infos[int(id)] = info[id]
			changed.append(int(id))
	var now := _now()
	var seen := {}
	for p: Array in msg.get("p", []):
		var id := int(p[0])
		seen[id] = true
		players[id] = {"x": float(p[1]), "y": float(p[2]), "d": int(p[3]), "m": int(p[4]), "t": now}
	for id: int in players.keys():
		if not seen.has(id):
			players.erase(id)
	players_updated.emit()
	if not changed.is_empty():
		info_updated.emit(changed)


func _send_visibility() -> void:
	if is_online():
		_send({"t": "vis", "v": GameSettings.online_visible})


func _send(msg: Dictionary) -> void:
	if _socket and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		# full_precision: las celdas globales (~16 millones) necesitan sus decimales.
		_socket.send_text(JSON.stringify(msg, "", false, true))


func _set_status(new_status: String) -> void:
	if new_status == "connecting" or new_status == "offline":
		_last_ping = 0.0
	if status != new_status:
		status = new_status
		status_changed.emit(new_status)


func _clear() -> void:
	my_id = 0
	players.clear()
	radar.clear()
	players_updated.emit()
	radar_updated.emit()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
