extends Node
## Mecánicas del juego: morral, lugares, fabricación, encargos, historia,
## territorio, logros y objetos del mapa. Autoload "Game".
##
## El servidor es la fuente de verdad (apps/backend/app/game): aquí se guarda lo
## último que dijo y se le piden las acciones. Toda acción responde con el
## jugador al día (stats, morral, historia) y con "eventos": recompensas,
## logros, diálogos… que la interfaz muestra (señal events_received).
##
## Uso típico:
##     var res := await Game.buy(poi_ref, "pan", 2)
##     if not res.ok: hud.show_message(res.message)

## Cambió el morral, la historia, los encargos o los logros.
signal changed
## Llegaron eventos para mostrar: Array de Dictionary { type, … }
## (toast, reward, discover, achievement, dialog, story, sector).
signal events_received(events: Array)
## Cambió un objeto del mapa cerca: op "put" (data = objeto) o "del" (data = { id }).
signal object_changed(op: String, data: Dictionary)
## Cambió la información del sector donde está el jugador.
signal territory_changed

const PREFIX := "/api/v1/game"

## Catálogo (no cambia en la partida): objetos, recetas, logros, personajes…
var catalog := {}
var items := {}  # key -> definición
var recipes: Array = []
var achievement_defs: Array = []
var npcs := {}
var ranks: Array = []
var sign_phrases: Array = []
var sector_cells := 128
var near_cells := 7.0

## Estado del jugador.
var inventory := {}  # key -> cantidad
var slots := 16
var story := {}
var jobs: Array = []
var achievements := {}  # key -> true
var counters := {}
## Sectores alrededor: { here: {sx, sy}, sectors: [...], rent: {...} }
var territory := {}

var ready_to_play := false
## Ventanas abiertas que pausan el juego (ver GameWindow).
var _modals := 0
var _refresh_queued := false
var _territory_queued := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Online.game_events.connect(_on_online_events)
	Online.object_message.connect(func(msg: Dictionary) -> void:
		if str(msg.get("op", "")) == "del":
			object_changed.emit("del", {"id": int(msg.get("id", 0))})
		elif msg.get("o") is Dictionary:
			object_changed.emit("put", msg.o))
	Auth.session_changed.connect(func(user: Dictionary) -> void:
		if user.is_empty():
			_clear())


## Carga el catálogo (una vez) y el estado del jugador. Lo llama el mundo al entrar.
func start() -> bool:
	if catalog.is_empty():
		var res := await Api.request_json(HTTPClient.METHOD_GET, PREFIX + "/catalog")
		if not res.ok or not (res.data is Dictionary):
			return false
		_apply_catalog(res.data)
	var state := await _call(HTTPClient.METHOD_GET, "/state")
	ready_to_play = state.ok
	return state.ok


func _clear() -> void:
	inventory = {}
	story = {}
	jobs = []
	achievements = {}
	counters = {}
	territory = {}
	ready_to_play = false
	changed.emit()


# --- Consultas ----------------------------------------------------------------------

func item(key: String) -> Dictionary:
	return items.get(key, {"key": key, "name": key, "desc": "", "kind": "material", "price": 0})


func item_name(key: String) -> String:
	return str(item(key).get("name", key))


func count(key: String) -> int:
	return int(inventory.get(key, 0))


func npc(key: String) -> Dictionary:
	return npcs.get(key, {"key": key, "name": key, "role": "", "portrait": "vecino"})


func level() -> int:
	return int(PlayerStats.get_stat("xp").get("level", {}).get("level", 1))


func is_hungry() -> bool:
	return PlayerStats.has_stats() and PlayerStats.value("hunger", 100.0) <= 0.5


## Sector de una celda global.
func sector_of(global_cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(global_cell.x) / sector_cells), floori(float(global_cell.y) / sector_cells))


## Datos del sector donde está el jugador (o {} si aún no se sabe).
func current_sector() -> Dictionary:
	var here: Dictionary = territory.get("here", {})
	for s: Dictionary in territory.get("sectors", []):
		if int(s.sx) == int(here.get("sx", -1)) and int(s.sy) == int(here.get("sy", -1)):
			return s
	return {}


func rank_name(rank: int) -> String:
	return str(ranks[rank].name) if rank >= 0 and rank < ranks.size() else ""


## Encargos activos y el paso que toca de cada uno: [{ job, step }].
func active_steps() -> Array:
	var out := []
	for job: Dictionary in jobs:
		if job.get("status") != "active":
			continue
		for step: Dictionary in job.get("steps", []):
			if not step.get("done", false):
				out.append({"job": job, "step": step})
				if step.get("type") != "visit":
					break
	return out


## Meta de la historia que pide hablar con alguien: { npc, cats } o {}.
func talk_goal() -> Dictionary:
	for goal: Dictionary in story.get("goals", []):
		if goal.get("type") == "talk" and not goal.get("done", false):
			return goal
	return {}


## Se puede fabricar la receta con lo que hay en el morral (sin mirar la estación).
func can_craft(recipe: Dictionary) -> bool:
	if level() < int(recipe.get("level", 1)):
		return false
	if recipe.get("tool") != null and count(str(recipe.tool)) == 0:
		return false
	for key: String in recipe.inputs:
		if count(key) < int(recipe.inputs[key]):
			return false
	return true


# --- Acciones -----------------------------------------------------------------------
# Todas devuelven { ok, message, data }. `poi` es { id, cx, cy }.

func refresh() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/state")


func visit(poi: Dictionary) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/places/visit", {"poi": poi})


func buy(poi: Dictionary, item_key: String, qty: int) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/places/buy", {"poi": poi, "item": item_key, "qty": qty})


func sell(poi: Dictionary, item_key: String, qty: int) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/places/sell", {"poi": poi, "item": item_key, "qty": qty})


func work(poi: Dictionary) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/places/work", {"poi": poi})


func service(poi: Dictionary, key: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/places/service", {"poi": poi, "service": key})


func gather(global_cell: Vector2i) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/gather", {"x": global_cell.x, "y": global_cell.y})


func use_item(item_key: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/items/use", {"item": item_key})


func craft(recipe_key: String, times := 1) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/craft", {"recipe": recipe_key, "times": times})


func refresh_jobs() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/jobs")


func new_jobs() -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/jobs/refresh", {})


func accept_job(id: int) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/jobs/%d/accept" % id, {})


func abandon_job(id: int) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/jobs/%d/abandon" % id, {})


func job_step(id: int, poi: Dictionary) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/jobs/%d/step" % id, {"poi": poi})


## Hablar con el personaje de la historia en un lugar (o por teléfono, sin lugar).
func story_talk(poi: Variant = null) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/story/talk", {"poi": poi} if poi != null else {})


func story_seen() -> void:
	if story.get("dialog") != null:
		story.dialog = null
		_call(HTTPClient.METHOD_POST, "/story/seen", {})


func refresh_territory() -> void:
	var res := await _call(HTTPClient.METHOD_GET, "/territory")
	if res.ok:
		territory = res.data
		territory_changed.emit()
		changed.emit()


func collect_rent() -> Dictionary:
	var res := await _call(HTTPClient.METHOD_POST, "/territory/collect", {})
	if res.ok:
		territory.rent = res.data.get("rent", {})
		territory_changed.emit()
	return res


## Objetos del mapa en un rectángulo de chunks: Array de { id, kind, x, y, owner, ownerName, state }.
func objects_in(from_chunk: Vector2i, to_chunk: Vector2i) -> Array:
	var path := "/objects?cx0=%d&cy0=%d&cx1=%d&cy1=%d" % [from_chunk.x, from_chunk.y, to_chunk.x, to_chunk.y]
	var res := await Api.request_json(HTTPClient.METHOD_GET, PREFIX + path)
	if res.ok and res.data is Dictionary and res.data.get("objects") is Array:
		return res.data.objects
	return []


func place_object(item_key: String, global_cell: Vector2i) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/objects", {"item": item_key, "x": global_cell.x, "y": global_cell.y})


## Acción sobre un objeto del mapa: "look", "pickup", "water", "buy"… con sus argumentos.
func object_action(id: int, action: String, args := {}) -> Dictionary:
	var body := {"action": action}
	body.merge(args)
	return await _call(HTTPClient.METHOD_POST, "/objects/%d/act" % id, body)


## Solo desarrollo: "give" { item, qty }, "influence" { points }, "skip", "reset".
func dev(action: String, args := {}) -> Dictionary:
	var body := {"action": action}
	body.merge(args)
	return await _call(HTTPClient.METHOD_POST, "/dev", body)


# --- Ventanas -----------------------------------------------------------------------

## Las ventanas del juego pausan el mundo mientras están abiertas (como el menú).
func push_modal() -> void:
	_modals += 1
	get_tree().paused = true


func pop_modal() -> void:
	_modals = maxi(_modals - 1, 0)
	if _modals == 0:
		get_tree().paused = false


func has_modal() -> bool:
	return _modals > 0


# --- Interno ------------------------------------------------------------------------

func _call(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	var res := await Api.request_json(method, PREFIX + path, body)
	if res.status == 401:
		Auth.refresh_profile()  # el token caducó: Auth cierra la sesión
	var data: Dictionary = res.data if res.data is Dictionary else {}
	if not res.ok:
		var message := str(data.get("message", ""))
		if message.is_empty():
			message = "Sin conexión con el servidor." if res.status == 0 else "No se pudo hacer eso (%s)." % res.error
		return {"ok": false, "message": message, "data": data, "code": str(data.get("error", ""))}
	_apply(data)
	# Casi toda acción mueve la influencia del sector: se pone al día (sin amontonar peticiones).
	if method == HTTPClient.METHOD_POST and not path.begins_with("/story/seen"):
		_queue_territory_refresh()
	return {"ok": true, "message": "", "data": data, "code": ""}


func _queue_territory_refresh() -> void:
	if _territory_queued or territory.is_empty():
		return
	_territory_queued = true
	await get_tree().create_timer(0.8, true, false, true).timeout
	_territory_queued = false
	refresh_territory()


func _apply(data: Dictionary) -> void:
	if data.get("stats") is Array:
		PlayerStats.apply(data.stats)
	if data.get("inventory") is Dictionary:
		inventory = data.inventory.get("items", {})
		slots = int(data.inventory.get("slots", slots))
	if data.get("story") is Dictionary:
		story = data.story
	if data.get("jobs") is Array:
		jobs = data.jobs
	if data.get("achievements") is Array:
		achievements = {}
		for key: String in data.achievements:
			achievements[key] = true
	if data.get("counters") is Dictionary:
		counters = data.counters
	var events: Array = data.get("events", []) if data.get("events") is Array else []
	_note_events(events)
	changed.emit()
	if not events.is_empty():
		events_received.emit(events)


func _note_events(events: Array) -> void:
	for event: Dictionary in events:
		match event.get("type"):
			"achievement":
				achievements[str(event.key)] = true
			"sector":
				refresh_territory()


## Eventos que llegan por el multijugador (metros caminados, ventas del puesto,
## sectores perdidos…): se muestran y se pide el estado, que pudo cambiar.
func _on_online_events(events: Array) -> void:
	_note_events(events)
	events_received.emit(events)
	if _refresh_queued:
		return
	_refresh_queued = true
	await get_tree().create_timer(0.3, true, false, true).timeout
	_refresh_queued = false
	refresh()


func _apply_catalog(data: Dictionary) -> void:
	catalog = data
	items = {}
	for def: Dictionary in data.get("items", []):
		items[def.key] = def
	recipes = data.get("recipes", [])
	achievement_defs = data.get("achievements", [])
	npcs = data.get("npcs", {})
	ranks = data.get("ranks", [])
	sign_phrases = data.get("signPhrases", [])
	var rules: Dictionary = data.get("rules", {})
	sector_cells = int(rules.get("sectorCells", sector_cells))
	near_cells = float(rules.get("nearCells", near_cells))
