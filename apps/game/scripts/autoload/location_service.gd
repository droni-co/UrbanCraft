extends Node
## Ubicación real del jugador. Autoload "LocationService".
##
## Fuentes, en orden de prioridad:
##   1. Argumentos:  godot --path apps/game -- --lat=40.42 --lon=-3.6887
##   2. GPS del dispositivo (TODO: requiere un plugin de Android/iOS)
##   3. Ajustes de proyecto urbancraft/map/default_latitude/longitude
##
## Modo híbrido: esta ubicación es el "ancla". El jugador se mueve libremente
## dentro de un radio (playRadiusMeters del servidor) alrededor de ella.

signal location_changed(latitude: float, longitude: float)

const SETTING_LAT := "urbancraft/map/default_latitude"
const SETTING_LON := "urbancraft/map/default_longitude"

var latitude := 0.0
var longitude := 0.0
## "args", "gps" o "default"
var source := "default"


func _ready() -> void:
	latitude = ProjectSettings.get_setting(SETTING_LAT, 40.4200)
	longitude = ProjectSettings.get_setting(SETTING_LON, -3.6887)

	var args := _parse_args()
	if args.has("lat") and args.has("lon"):
		latitude = clampf(float(args.lat), -85.0, 85.0)
		longitude = wrapf(float(args.lon), -180.0, 180.0)
		source = "args"


func has_gps() -> bool:
	return false  # TODO: integrar plugin de geolocalización para Android/iOS


## Para el plugin de GPS (o pruebas): actualiza la ubicación real.
func set_location(lat: float, lon: float, from_source := "gps") -> void:
	latitude = lat
	longitude = lon
	source = from_source
	location_changed.emit(lat, lon)


func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var parts := arg.substr(2).split("=", true, 1)
			out[parts[0]] = parts[1]
	return out
