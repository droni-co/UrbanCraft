class_name Sun
extends RefCounted
## Altura del sol sobre el horizonte para una hora UTC y un lugar.
##
## Así el ciclo de día y noche coincide con el amanecer y el atardecer reales
## de donde está el jugador (y con la estación del año), sin depender de la
## zona horaria del dispositivo. Fórmulas aproximadas del NOAA / Almanaque
## Náutico (error < 1°, de sobra para la luz del juego).


## Grados sobre el horizonte (negativo = de noche).
static func elevation(unix_seconds: float, latitude: float, longitude: float) -> float:
	var d := unix_seconds / 86400.0 - 10957.5  # días desde J2000.0
	var g := deg_to_rad(fposmod(357.529 + 0.98560028 * d, 360.0))
	var q := fposmod(280.459 + 0.98564736 * d, 360.0)
	var ecliptic := deg_to_rad(q + 1.915 * sin(g) + 0.020 * sin(2.0 * g))
	var obliquity := deg_to_rad(23.439 - 0.00000036 * d)
	var right_ascension := atan2(cos(obliquity) * sin(ecliptic), cos(ecliptic))
	var declination := asin(sin(obliquity) * sin(ecliptic))
	var sidereal_hours := fposmod(18.697374558 + 24.06570982441908 * d, 24.0)
	var hour_angle := deg_to_rad(sidereal_hours * 15.0 + longitude) - right_ascension
	var lat := deg_to_rad(latitude)
	return rad_to_deg(asin(sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hour_angle)))


## Hora solar local aproximada (0-24) para mostrar en pantalla.
static func local_solar_hour(unix_seconds: float, longitude: float) -> float:
	return fposmod(unix_seconds / 3600.0 + longitude / 15.0, 24.0)
