extends Node
## Música y efectos de sonido. Autoload "GameAudio".
##
## Dos buses con su propio volumen (GameSettings.music_volume / sfx_volume, que
## se cambian en Menú → Ajustes):
##   - "Music": la música de fondo. De día suenan los temas de día uno tras otro
##     (Day01 → Day02 → …) y de noche el tema de noche. La pantalla de inicio usa
##     siempre un tema de día. Al cambiar de tema se funden.
##   - "SFX": efectos de las acciones (comer, recoger, entrar a un lugar…),
##     avisos y el ambiente del mundo (pájaros, grillos, agua; ver AmbientSounds).
##
## Los efectos se piden por nombre: `GameAudio.play("ring")` (ver SOUNDS).
## Muchas acciones suenan solas: se escuchan las señales de Game
## (action_finished, events_received) y no hace falta tocar cada pantalla.
##
## Los archivos están en assets/audio/ (music/, sfx/, ui/, ambient/).

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const AUDIO_DIR := "res://assets/audio/"

const DAY_TRACKS: Array[String] = ["music/Day01.ogg", "music/Day02.ogg"]
const NIGHT_TRACK := "music/Night.ogg"
## Volumen base de la música (el del jugador se aplica en el bus).
const MUSIC_DB := -4.0
const FADE_SECONDS := 2.5
## Silencio entre un tema y el siguiente.
const MUSIC_GAP_SECONDS := 3.0

## Efectos: nombre -> {files, db, max (segundos; 0 = entero)}. Los sonidos largos
## se cortan con un fundido para que no se queden sonando sobre la interfaz.
const SOUNDS := {
	"teleport": {"files": ["sfx/teleport.wav"], "db": -2.0},
	"door_open": {"files": ["ui/dooropen.wav"], "db": -3.0},
	"door_locked": {"files": ["ui/lockeddoor.wav"], "db": -5.0},
	"eat": {"files": ["ui/eating.wav"], "db": -3.0},
	"cloth": {"files": ["ui/headwear.wav"], "db": -5.0, "max": 0.9},
	"gather": {"files": ["ui/picklock.wav"], "db": -5.0, "max": 1.4},
	"fail": {"files": ["ui/picklock-fail.wav"], "db": -7.0, "max": 1.2},
	"ring": {"files": ["ui/ring.wav"], "db": -6.0},
	"scroll": {"files": ["ui/scroll.wav"], "db": -8.0, "max": 0.8},
	"build": {"files": ["ambient/build1.wav", "ambient/build2.wav", "ambient/smith1.wav", "ambient/smith2.wav"], "db": -5.0, "max": 2.0},
	"cook": {"files": ["ambient/alchemist1.wav", "ambient/alchemist2.wav", "ambient/bubbles.wav"], "db": -5.0, "max": 2.5},
	"grill": {"files": ["ambient/fireplace.wav"], "db": -4.0, "max": 2.5},
	"clock": {"files": ["ambient/clock.wav"], "db": -8.0},
}
## Un mismo efecto no se repite antes de esto (varias señales por una acción).
const REPEAT_GUARD_MS := 150
const SFX_VOICES := 6
const AMBIENT_VOICES := 4

var _streams := {}  # ruta -> AudioStream
var _last_played := {}  # nombre -> ms
var _sfx: Array[AudioStreamPlayer] = []
var _ambient: Array[AudioStreamPlayer] = []

## Dos reproductores para fundir un tema con el siguiente.
var _music: Array[AudioStreamPlayer] = []
var _music_active := 0
var _track := ""
var _night := false
var _day_index := 0
var _music_tween: Tween
var _gap_timer: SceneTreeTimer


func _ready() -> void:
	# La música y los avisos siguen con el juego en pausa (menús abiertos).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	for i in 2:
		var player := _make_player(MUSIC_BUS)
		player.finished.connect(_on_track_finished.bind(player))
		_music.append(player)
	for i in SFX_VOICES:
		_sfx.append(_make_player(SFX_BUS))
	for i in AMBIENT_VOICES:
		# El ambiente se pausa con el juego (menús abiertos).
		var player := _make_player(SFX_BUS)
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		_ambient.append(player)

	GameSettings.audio_settings_changed.connect(_apply_volumes)
	_apply_volumes()
	Game.action_finished.connect(_on_action)
	Game.events_received.connect(_on_events)
	Friends.notified.connect(func(_event: String, _nickname: String) -> void: play("ring"))


# --- Música -----------------------------------------------------------------------

## Pantalla de inicio: un tema de día (sigue el que suene si ya es de día).
func play_day_music() -> void:
	_night = false
	if _track in DAY_TRACKS and _is_music_playing():
		return
	_play_track(DAY_TRACKS[_day_index % DAY_TRACKS.size()])


## El mundo avisa si es de noche: cambia al tema de noche (o vuelve a los de día).
func set_night(is_night: bool) -> void:
	if is_night == _night and _is_music_playing():
		return
	_night = is_night
	if is_night:
		_play_track(NIGHT_TRACK)
	elif not _track in DAY_TRACKS:
		_day_index = (_day_index + 1) % DAY_TRACKS.size()
		_play_track(DAY_TRACKS[_day_index])


func _play_track(path: String) -> void:
	_gap_timer = null
	var stream := _stream(path)
	if stream == null:
		return
	_track = path
	var old := _music[_music_active]
	_music_active = 1 - _music_active
	var player := _music[_music_active]
	player.stream = stream
	player.volume_db = -40.0
	player.play()
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel()
	_music_tween.tween_property(player, "volume_db", MUSIC_DB, FADE_SECONDS)
	if old.playing:
		_music_tween.tween_property(old, "volume_db", -40.0, FADE_SECONDS)
		_music_tween.chain().tween_callback(old.stop)


func _is_music_playing() -> bool:
	return _music[_music_active].playing or _gap_timer != null


## Al terminar un tema: tras una pausa corta, el siguiente de día o se repite el de noche.
func _on_track_finished(player: AudioStreamPlayer) -> void:
	if player != _music[_music_active]:
		return
	var timer := get_tree().create_timer(MUSIC_GAP_SECONDS, true)
	_gap_timer = timer
	await timer.timeout
	if _gap_timer != timer:
		return  # mientras tanto empezó otro tema
	if _night:
		_play_track(NIGHT_TRACK)
	else:
		_day_index = (_day_index + 1) % DAY_TRACKS.size()
		_play_track(DAY_TRACKS[_day_index])


# --- Efectos ------------------------------------------------------------------------

## Reproduce un efecto de SOUNDS. `volume_db` se suma a su volumen.
func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var def: Dictionary = SOUNDS.get(sound, {})
	if def.is_empty():
		push_warning("[GameAudio] Efecto desconocido: %s" % sound)
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound, -100000)) < REPEAT_GUARD_MS:
		return
	_last_played[sound] = now
	var files: Array = def.files
	_play_on(_sfx, str(files.pick_random()), float(def.get("db", 0.0)) + volume_db,
		pitch * randf_range(0.96, 1.04), float(def.get("max", 0.0)))


## Sonido de ambiente (ruta relativa a assets/audio/), en sus propias voces para
## no cortar los efectos de la interfaz.
func play_ambient(path: String, volume_db := 0.0, max_seconds := 0.0) -> void:
	_play_on(_ambient, path, volume_db, randf_range(0.93, 1.07), max_seconds)


func _play_on(pool: Array[AudioStreamPlayer], path: String, volume_db: float, pitch: float, max_seconds: float) -> void:
	var stream := _stream(path)
	if stream == null:
		return
	var player := _free_voice(pool)
	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()
	if max_seconds > 0.0 and stream.get_length() > max_seconds + 0.1:
		var stream_at := player.stream
		var fade := create_tween()
		fade.tween_interval(max_seconds - 0.25)
		fade.tween_callback(func() -> void:
			if player.stream == stream_at and player.playing:
				var out := create_tween()
				out.tween_property(player, "volume_db", volume_db - 30.0, 0.25)
				out.tween_callback(func() -> void:
					if player.stream == stream_at:
						player.stop()))


## Una voz libre o, si todas suenan, la que lleva más tiempo sonando.
func _free_voice(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	var oldest := pool[0]
	for player in pool:
		if not player.playing:
			return player
		if player.get_playback_position() > oldest.get_playback_position():
			oldest = player
	return oldest


# --- Sonidos de las acciones del juego ------------------------------------------------

## Cada acción contra el servidor (Game._call) suena según cómo le fue.
func _on_action(path: String, body: Variant, ok: bool) -> void:
	var args: Dictionary = body if body is Dictionary else {}
	match path:
		"/items/use":
			if ok:
				play("eat" if str(Game.item(str(args.get("item", ""))).get("kind", "")) == "food" else "cloth")
		"/craft":
			if ok:
				play(_craft_sound(str(args.get("recipe", ""))))
		"/places/visit":
			play("door_open" if ok else "door_locked")
		"/places/buy", "/places/sell", "/places/service", "/territory/collect":
			if ok:
				play("ring")
		"/places/work", "/objects":
			if ok:
				play("build")
		_:
			if ok and path.begins_with("/jobs/") and path.ends_with("/step"):
				play("ring")


## Cocinar (comida en la parrilla o en la olla) o construir.
func _craft_sound(recipe_key: String) -> String:
	for recipe: Dictionary in Game.recipes:
		if str(recipe.get("key", "")) != recipe_key:
			continue
		if str(Game.item(str(recipe.get("output", ""))).get("kind", "")) == "food":
			return "grill" if str(recipe.get("station", "")) == "parrilla" else "cook"
		break
	return "build"


## Avisos del servidor: logros, lugares nuevos, historia, territorio.
func _on_events(events: Array) -> void:
	for event: Dictionary in events:
		match event.get("type"):
			"achievement":
				play("ring", 2.0, 1.12)
			"discover":
				play("ring")
			"reward":
				if event.get("money") != null:
					play("ring")
			"story", "dialog":
				play("scroll")
			"sector":
				if event.get("kind") == "owned":
					play("ring", 2.0, 1.12)


# --- Volumen y buses ----------------------------------------------------------------

func _apply_volumes() -> void:
	_set_bus_volume(MUSIC_BUS, GameSettings.music_volume)
	_set_bus_volume(SFX_BUS, GameSettings.sfx_volume)


func _set_bus_volume(bus: StringName, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, volume <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.001)))


## Los buses vienen de default_bus_layout.tres. Crearlos aquí es solo un
## respaldo: en la web (reproducción por "samples") un bus creado en tiempo de
## ejecución deja mal conectado el mezclador del navegador y no suena nada.
func _ensure_bus(bus: StringName) -> void:
	if AudioServer.get_bus_index(bus) >= 0:
		return
	push_warning("[GameAudio] Falta el bus %s en default_bus_layout.tres; se crea en tiempo de ejecución." % bus)
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus)
	AudioServer.set_bus_send(index, &"Master")


func _make_player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var stream := load(AUDIO_DIR + path) as AudioStream
	if stream == null:
		push_warning("[GameAudio] No se encontró el sonido %s" % path)
	_streams[path] = stream
	return stream
