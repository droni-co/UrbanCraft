class_name RemotePlayers
extends Node
## Pone en el mundo a los demás jugadores cercanos (Online.players) y los quita
## cuando se alejan o se desconectan. Los avatares (RemotePlayer) se agregan a
## `container` (Entities, con y_sort) para que se ordenen con el resto.
##
## `to_world` convierte celdas GLOBALES (float de 64 bits) a posición del mundo;
## lo da world.gd, que conoce el origen de los chunks y la forma de los tiles.

var container: Node2D
var to_world: Callable

var _avatars := {}  # id -> RemotePlayer


func _ready() -> void:
	Online.players_updated.connect(_sync)
	Online.action_received.connect(_on_action)
	Online.info_updated.connect(_on_info)
	Online.chat_received.connect(_on_chat)


func count() -> int:
	return _avatars.size()


func _sync() -> void:
	if container == null or not to_world.is_valid():
		return
	for id: int in _avatars.keys():
		if not Online.players.has(id):
			_avatars[id].queue_free()
			_avatars.erase(id)
	for id: int in Online.players:
		var state: Dictionary = Online.players[id]
		var avatar: RemotePlayer = _avatars.get(id)
		if avatar == null:
			avatar = RemotePlayer.new()
			avatar.player_id = id
			avatar.name = "Remote_%d" % id
			container.add_child(avatar)
			_avatars[id] = avatar
			avatar.set_info(Online.nickname(id), Online.level(id), Online.skin(id))
		var pos: Vector2 = to_world.call(float(state.x), float(state.y))
		avatar.push_state(float(state.t), pos, int(state.d), int(state.m))


## Cambió el apodo, nivel o personaje de jugadores que ya están en pantalla.
func _on_info(ids: Array) -> void:
	for id: int in ids:
		var avatar: RemotePlayer = _avatars.get(id)
		if avatar:
			avatar.set_info(Online.nickname(id), Online.level(id), Online.skin(id))


func _on_chat(player_id: int, _nickname: String, text: String, _friend: bool) -> void:
	var avatar: RemotePlayer = _avatars.get(player_id)
	if avatar:
		avatar.show_chat(text)


func _on_action(player_id: int, kind: String) -> void:
	var avatar: RemotePlayer = _avatars.get(player_id)
	if avatar:
		avatar.show_action(kind)
