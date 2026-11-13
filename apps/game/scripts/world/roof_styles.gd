class_name RoofStyles
extends RefCounted
## Tejados por edificio.
##
## El servidor manda, por celda de edificio, un byte de techo (ver roofByte en
## apps/backend/app/map/rasterizer.ts): qué parte del tejado de su edificio cae
## ahí (plano, faldón bajo, faldón alto o cumbrera), hacia dónde corre la
## cumbrera y un tono para todo el edificio.
##
## Los bloques del atlas de edificios traen un techo plano. En vez de multiplicar
## el atlas por cada combinación (pesaría cientos de MB a x4), cada combinación es
## un "tile alternativo" del TileSet (mismo dibujo, sin memoria extra) con un
## material: un shader que repinta el rombo del techo con la teja orientada,
## sombreada según hacia dónde mira el faldón y con el tono del edificio.
## Las alternativas se crean al vuelo la primera vez que se usan.

const PART_MASK := 3
const AXIS_Y := 8
const TINT_SHIFT := 4
## Columnas del atlas de edificios con tejado a dos aguas (WorldTiles.BUILDING_STYLES).
const PITCHED_COLUMNS := 2

const SHADER := """
shader_type canvas_item;

uniform sampler2D clay : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D clay_red : source_color, repeat_enable, filter_linear_mipmap;
uniform int part = 0;
uniform bool axis_y = false;
uniform int tint = 0;
// Columnas y filas del atlas de edificios (estilos x variantes).
uniform vec2 grid = vec2(6.0, 4.0);
// De noche (0-1) se encienden algunas ventanas.
uniform float night = 0.0;

varying vec4 modulate;
varying vec2 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

const vec3 CLAY_TINTS[4] = vec3[](vec3(1.0), vec3(1.07, 0.95, 0.86), vec3(0.9, 0.84, 0.84), vec3(1.03, 1.0, 0.95));
const float FLAT_TINTS[4] = float[](1.0, 1.05, 0.94, 0.98);

void vertex() {
	modulate = COLOR;
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 atlas = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 stride = atlas / grid;
	vec2 px = UV * atlas;
	float col = floor(px.x / stride.x);
	vec2 local = px - floor(px / stride) * stride;
	// Rombo del techo (arriba de cada región, 256x128 px de arte).
	float dx = (local.x - 128.0) / 128.0;
	float dy = (local.y - 64.0) / 64.0;
	if (COLOR.a > 0.0 && abs(dx) + abs(dy) <= 0.97) {
		float u = (dx + local.y / 64.0) * 0.5;  // a lo largo del eje x de la grilla
		float v = (local.y / 64.0 - dx) * 0.5;  // a lo largo del eje y
		if (part > 0 && col < 1.5) {  // columnas 0 y 1: casas y ladrillo (PITCHED_COLUMNS)
			// Coordenada a lo largo de la cumbrera (t) y a través de ella (s).
			float t = axis_y ? v : u;
			float s = axis_y ? u : v;
			int p = part == 3 ? (s < 0.5 ? 1 : 2) : part;
			// Las hiladas de teja corren paralelas a la cumbrera y bajan hacia cada alero.
			vec2 tc = vec2(t, p == 1 ? 1.0 - s : s);
			vec3 c = (col < 0.5 ? texture(clay, tc) : texture(clay_red, tc)).rgb;
			// Sol arriba a la izquierda: el faldón que mira a -x es el más iluminado,
			// el que mira a -y (se aleja de la cámara) el más oscuro.
			float light = axis_y ? (p == 1 ? 1.12 : 0.84) : (p == 1 ? 0.76 : 1.05);
			c *= light;
			if (part == 3) {
				// Caballete: una franja de tejas sobre la cumbrera con su sombra.
				float d = abs(s - 0.5);
				vec3 cap = texture(clay, vec2(t * 3.0, 0.25)).rgb * 1.12;
				c = mix(c, c * 0.62, smoothstep(0.075, 0.055, d) * smoothstep(0.03, 0.055, d));
				c = mix(c, cap, smoothstep(0.045, 0.03, d));
			}
			COLOR.rgb = c * CLAY_TINTS[tint] * modulate.rgb;
		} else {
			COLOR.rgb *= FLAT_TINTS[tint];
		}
	} else if (night > 0.0 && COLOR.a > 0.0) {
		// Paredes: los vidrios (azulados) de algunas ventanas se encienden.
		vec3 c = COLOR.rgb;
		float glass = smoothstep(0.04, 0.14, c.b - c.r) * step(0.3, c.b);
		// Se decide por ventana: edificio (origen del tile), fachada, piso
		// (26 px lógicos) y columna, no por píxel, para que cada ventana se
		// encienda entera.
		vec2 origin = floor(world - local / 4.0 + 0.5);  // px de arte a x4
		float side = step(128.0, local.x);
		float depth = local.y + abs(local.x - 128.0) * 0.5 - 128.0;
		float storey = floor(depth / 104.0);
		float wcol = floor(abs(local.x - 128.0) / 43.0);
		float on = step(hash(origin + vec2(side * 17.0 + wcol * 5.0, storey * 13.0)), 0.42);
		vec3 warm = vec3(1.0, 0.86, 0.5) * (0.92 + 0.08 * c.b);
		COLOR.rgb = mix(c, warm * modulate.rgb, glass * on * smoothstep(0.2, 0.7, night));
	}
}
"""

static var _shader: Shader
static var _materials := {}  # byte de techo -> ShaderMaterial
static var _night := 0.0


## Material para las capas de edificios (los bloques sin datos de techo):
## techo plano tal cual, pero con las ventanas que se encienden de noche.
static func layer_material() -> ShaderMaterial:
	return _material(0)


## Cuánto es de noche (0-1): enciende las ventanas.
static func set_night(value: float) -> void:
	if is_equal_approx(value, _night):
		return
	_night = value
	for material: ShaderMaterial in _materials.values():
		material.set_shader_parameter("night", value)


## Alternativa del tile `coords` de la fuente `source` para un byte de techo
## (0 = la normal). La crea si hace falta.
static func alternative(tile_set: TileSet, source_id: int, coords: Vector2i, roof: int) -> int:
	if roof <= 0 or tile_set == null:
		return 0
	var alt := roof
	var source := tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null or not source.has_tile(coords):
		return 0
	if not source.has_alternative_tile(coords, alt):
		source.create_alternative_tile(coords, alt)
		var base := source.get_tile_data(coords, 0)
		var data := source.get_tile_data(coords, alt)
		data.texture_origin = base.texture_origin
		data.y_sort_origin = base.y_sort_origin
		data.z_index = base.z_index
		data.material = _material(roof)
	return alt


static func _material(roof: int) -> ShaderMaterial:
	if _materials.has(roof):
		return _materials[roof]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("clay", load("res://assets/tiles/roof_clay.png"))
	material.set_shader_parameter("clay_red", load("res://assets/tiles/roof_clay_red.png"))
	material.set_shader_parameter("part", roof & PART_MASK)
	material.set_shader_parameter("axis_y", (roof & AXIS_Y) != 0)
	material.set_shader_parameter("tint", (roof >> TINT_SHIFT) & 3)
	material.set_shader_parameter("grid", Vector2(WorldTiles.BUILDING_STYLES.size(), WorldTiles.building_variants()))
	material.set_shader_parameter("night", _night)
	_materials[roof] = material
	return material
