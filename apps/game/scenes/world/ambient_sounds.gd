class_name AmbientSounds
extends Node
## Ambiente del mundo, con los sonidos de assets/audio/ambient:
##
## - De día: pájaros (más seguido), gaviotas cerca del agua y, de vez en cuando,
##   ruidos de la ciudad (un caballo, obras).
## - Al atardecer y de noche: grillos, cuervos y alguna chimenea.
## - Cerca del agua: olas y corriente; cerca de una fuente, su chorro. Más
##   fuerte cuanto más cerca.
## - Al anochecer y al amanecer suena el reloj, y la música cambia de tema
##   (GameAudio.set_night).
##
## Todo va al bus de efectos (Ajustes → Efectos).

## Sonidos sueltos: [archivo, peso, volumen dB].
const DAY := [
	["ambient/birds1.wav", 4.0, -14.0], ["ambient/birds2.wav", 4.0, -14.0],
	["ambient/birds3.wav", 4.0, -14.0], ["ambient/birds4.wav", 4.0, -14.0],
	["ambient/horse.wav", 0.6, -18.0],
	["ambient/build1.wav", 0.5, -22.0], ["ambient/build2.wav", 0.5, -22.0],
]
const DUSK := [
	["ambient/raven.wav", 2.0, -16.0], ["ambient/raven2.wav", 2.0, -16.0],
	["ambient/cricket1.wav", 1.0, -16.0],
]
const NIGHT := [
	["ambient/cricket1.wav", 5.0, -15.0], ["ambient/cricket2.wav", 5.0, -15.0],
	["ambient/raven2.wav", 0.6, -18.0], ["ambient/fireplace.wav", 0.6, -22.0],
]
const SEAGULLS := [["ambient/seagull1.wav", 1.0, -16.0], ["ambient/seagull2.wav", 1.0, -16.0]]
const WATER := ["ambient/water-wave1.wav", "ambient/water-wave2.wav", "ambient/water-wave3.wav",
	"ambient/water-wave4.wav", "ambient/stream.wav"]
const FOUNTAIN := "ambient/fountain.wav"

## Distancia (celdas) a la que se oye el agua o una fuente.
const WATER_RANGE := 10.0
const FOUNTAIN_RANGE := 6.0
## Volumen del agua junto a ella y a la máxima distancia.
const NEAR_DB := -12.0
const FAR_DB := -30.0

var day_night: DayNight
## Callable() -> {water: celdas, fountain: celdas} (INF si no hay cerca).
var nearby: Callable

var _near := {}  # lo último que devolvió `nearby`
var _next_call := 3.0
var _next_water := 1.0
var _is_night := false
var _started := false


func _process(delta: float) -> void:
	if day_night == null:
		return
	var night := day_night.night
	var is_night := night > 0.5
	if not _started or is_night != _is_night:
		if _started:
			GameAudio.play("clock")  # anochece / amanece
		_started = true
		_is_night = is_night
		GameAudio.set_night(is_night)

	_next_water -= delta
	if _next_water <= 0.0 and nearby.is_valid():
		_near = nearby.call()
		_next_water = 1.0
		_play_water(_near)

	_next_call -= delta
	if _next_call <= 0.0:
		var pool: Array = DAY
		if night > 0.85:
			pool = NIGHT
		elif night > 0.15:
			pool = DUSK
		elif _near.get("water", INF) <= WATER_RANGE and randf() < 0.35:
			pool = SEAGULLS
		var pick: Array = _weighted(pool)
		GameAudio.play_ambient(pick[0], pick[1])
		# Los grillos cantan seguido; los pájaros, cada tanto.
		_next_call = randf_range(2.5, 6.0) if pool == NIGHT else randf_range(5.0, 12.0)


## Agua o fuente cerca: un sonido de olas o del chorro y el siguiente al terminar.
func _play_water(near: Dictionary) -> void:
	var water: float = near.get("water", INF)
	var fountain: float = near.get("fountain", INF)
	if water <= WATER_RANGE:
		GameAudio.play_ambient(WATER.pick_random(), _by_distance(water, WATER_RANGE))
		_next_water = randf_range(1.6, 2.6)
	elif fountain <= FOUNTAIN_RANGE:
		GameAudio.play_ambient(FOUNTAIN, _by_distance(fountain, FOUNTAIN_RANGE))
		_next_water = 2.6


func _by_distance(distance: float, reach: float) -> float:
	return lerpf(NEAR_DB, FAR_DB, clampf(distance / reach, 0.0, 1.0))


func _weighted(pool: Array) -> Array:
	var total := 0.0
	for entry: Array in pool:
		total += float(entry[1])
	var t := randf() * total
	for entry: Array in pool:
		t -= float(entry[1])
		if t <= 0.0:
			return [entry[0], entry[2]]
	return [pool[-1][0], pool[-1][2]]
