extends Node
## Chat de texto entre jugadores. Autoload "Chat".
##
## Es público pero de alcance limitado (lo decide el servidor, ver docs/chat.md):
## lees a los jugadores de tu zona (tu chunk del mapa y los vecinos, ~450 m) y
## a tus amigos, estén donde estén. En modo fantasma solo te leen tus amigos.
##
## Guarda el historial de esta sesión (no se guarda en el servidor) y cuenta
## los mensajes sin leer mientras el panel está cerrado. La interfaz es
## ChatPanel (HUD); los globos sobre los personajes, ChatBubble.

## Nuevo mensaje en el historial (ver `messages` para el formato).
signal message_added(message: Dictionary)
signal unread_changed(count: int)

const MAX_LENGTH := 200
const HISTORY_SIZE := 100

## { id: int (0 = aviso del juego), nickname, text, friend: bool, mine: bool, system: bool }
var messages: Array[Dictionary] = []
var unread := 0
## true mientras el panel de chat está abierto (no cuenta como no leído).
var reading := false:
	set(value):
		reading = value
		if reading:
			_set_unread(0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Online.chat_received.connect(_on_chat)
	Online.chat_rejected.connect(func(retry: float) -> void:
		add_system("Vas muy rápido: espera %d s para volver a escribir." % ceili(retry)))
	Auth.session_changed.connect(func(user: Dictionary) -> void:
		if user.is_empty():
			messages.clear()
			_set_unread(0))


## Manda un mensaje. Devuelve "" si salió, o el motivo por el que no.
func send(text: String) -> String:
	var clean := text.strip_edges()
	if clean.is_empty():
		return "empty"
	if clean.length() > MAX_LENGTH:
		clean = clean.substr(0, MAX_LENGTH)
	if not Online.send_chat(clean):
		add_system("Sin conexión: el mensaje no se envió.")
		return "offline"
	return ""


## Aviso del juego dentro del chat (no se envía a nadie).
func add_system(text: String) -> void:
	_add({"id": 0, "nickname": "", "text": text, "friend": false, "mine": false, "system": true})


func _on_chat(player_id: int, nickname: String, text: String, friend: bool) -> void:
	var mine := player_id == Online.my_id
	_add({"id": player_id, "nickname": nickname, "text": text, "friend": friend, "mine": mine, "system": false})
	if not mine and not reading:
		_set_unread(unread + 1)


func _add(message: Dictionary) -> void:
	messages.append(message)
	if messages.size() > HISTORY_SIZE:
		messages.pop_front()
	message_added.emit(message)


func _set_unread(count: int) -> void:
	if count != unread:
		unread = count
		unread_changed.emit(unread)
