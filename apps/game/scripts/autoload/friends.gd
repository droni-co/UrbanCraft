extends Node
## Amigos y solicitudes de amistad. Autoload "Friends".
##
## El servidor guarda las amistades (apps/backend/app/services/friends_service.ts);
## este nodo las lee y las reparte. Se actualiza al conectarse al multijugador,
## cuando el servidor avisa por el WebSocket ({ t: "friends" }) y al abrir la
## sección "Amigos" del menú.
##
## friends:  [{ id, nickname, skin, online, friendshipId, since }]
## incoming: [{ id (de la solicitud), user: { id, nickname, skin }, createdAt }]
## outgoing: igual que incoming (solicitudes que enviaste)

## Cambió la lista de amigos o de solicitudes.
signal changed
## Aviso del servidor: event = "request" (te enviaron una solicitud) o
## "accepted" (aceptaron la tuya); nickname = el otro jugador.
signal notified(event: String, nickname: String)

const PREFIX := "/api/v1/friends"

var friends: Array = []
var incoming: Array = []
var outgoing: Array = []
var _refreshing := false


func _ready() -> void:
	# Las peticiones siguen con el juego en pausa (menú abierto).
	process_mode = Node.PROCESS_MODE_ALWAYS
	Online.friends_event.connect(_on_friends_event)
	Online.status_changed.connect(func(status: String) -> void:
		if status == "online":
			refresh())
	Auth.session_changed.connect(func(user: Dictionary) -> void:
		if user.is_empty():
			_apply({}))


func pending_count() -> int:
	return incoming.size()


## Vuelve a pedir amigos y solicitudes al servidor.
func refresh() -> void:
	if _refreshing or not Auth.is_signed_in():
		return
	_refreshing = true
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, PREFIX)
	_refreshing = false
	if res.ok and res.data is Dictionary:
		_apply(res.data)


## Busca un jugador por su apodo exacto.
## Devuelve { ok, user?: { id, nickname, skin, relation }, message }.
## relation: "none" | "friend" | "incoming" | "outgoing" | "self".
func search(nickname: String) -> Dictionary:
	var path := "%s/search?nickname=%s" % [PREFIX, nickname.strip_edges().uri_encode()]
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, path)
	if res.ok:
		return {"ok": true, "user": res.data.user, "message": ""}
	return {"ok": false, "message": _message(res, "No se pudo buscar")}


## Envía una solicitud de amistad. Si el otro ya te había enviado una, quedan
## como amigos directamente.
func send_request(nickname: String) -> Dictionary:
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_POST, PREFIX + "/requests",
		{"nickname": nickname.strip_edges()})
	if not res.ok:
		return {"ok": false, "message": _message(res, "No se pudo enviar la solicitud")}
	await refresh()
	var nick := str(res.data.user.nickname)
	if res.data.status == "accepted":
		return {"ok": true, "message": "¡Ahora eres amigo de %s!" % nick}
	return {"ok": true, "message": "Solicitud enviada a %s." % nick}


func accept(request_id: int) -> Dictionary:
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_POST,
		"%s/requests/%d/accept" % [PREFIX, request_id])
	await refresh()
	return {"ok": res.ok, "message": "" if res.ok else _message(res, "No se pudo aceptar")}


## Rechaza una solicitud recibida o cancela una enviada.
func reject(request_id: int) -> Dictionary:
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_DELETE,
		"%s/requests/%d" % [PREFIX, request_id])
	await refresh()
	return {"ok": res.ok, "message": "" if res.ok else _message(res, "No se pudo rechazar")}


func remove(user_id: int) -> Dictionary:
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_DELETE, "%s/%d" % [PREFIX, user_id])
	await refresh()
	return {"ok": res.ok, "message": "" if res.ok else _message(res, "No se pudo eliminar")}


## Dónde está un amigo ahora: { ok, lat, lon, message }. Solo si está
## conectado y visible (el modo fantasma lo oculta).
func locate(user_id: int) -> Dictionary:
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_GET,
		"%s/%d/location" % [PREFIX, user_id])
	if res.ok and res.data is Dictionary:
		return {"ok": true, "lat": float(res.data.lat), "lon": float(res.data.lon), "message": ""}
	if res.status == 409:
		refresh()  # su estado cambió: actualiza el "en línea"
	return {"ok": false, "message": _message(res, "No se pudo obtener su ubicación")}


# --- Interno ----------------------------------------------------------------------

func _on_friends_event(event: String, nickname: String) -> void:
	notified.emit(event, nickname)
	refresh()


func _apply(data: Dictionary) -> void:
	friends = data.get("friends", [])
	incoming = data.get("incoming", [])
	outgoing = data.get("outgoing", [])
	changed.emit()


## Mensaje legible de una respuesta de error del servidor.
func _message(res: Dictionary, fallback: String) -> String:
	if res.data is Dictionary and res.data.has("message"):
		return str(res.data.message)
	if res.status == 0:
		return "%s: sin conexión con el servidor." % fallback
	return "%s (%s)." % [fallback, res.error]
