class_name AmbientShaders
extends RefCounted
## Animaciones del ambiente que se hacen en la GPU, sin nodos extra:
##
## - Props: los árboles, pinos y arbustos se mecen con el viento. Cada tile es
##   un rectángulo; el shader corre los dos vértices de arriba (la copa) y deja
##   los de abajo, así el dibujo se inclina desde el pie. La fase depende de la
##   posición en el mundo y lleva ráfagas, para que no se muevan todos a la vez.
## - Suelo: brillos que se mueven sobre el agua.
##
## Los dos atlas son grillas regulares (tools/build_art.gd): con el paso de la
## grilla, el shader sabe en qué tipo de tile y en qué parte de él está.

const PROPS_SHADER := """
shader_type canvas_item;

// Paso de la grilla del atlas de props, en px de arte (región + separación).
uniform vec2 stride = vec2(260.0, 260.0);
uniform float region_height = 256.0;
// Cuánto se mece cada columna (tipo de prop) en px lógicos; 0 = no se mueve.
uniform float sway[10];
uniform float strength = 1.0;

void vertex() {
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	float col = floor(px.x / stride.x);
	float top = 1.0 - clamp((px.y - floor(px.y / stride.y) * stride.y) / region_height, 0.0, 1.0);
	float amp = sway[int(col)] * strength;
	if (amp > 0.0) {
		vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
		float phase = TIME * 1.4 + world.x * 0.045 + world.y * 0.03;
		float gust = 0.6 + 0.4 * sin(TIME * 0.37 + world.x * 0.004);
		VERTEX.x += (sin(phase) + 0.35 * sin(phase * 2.3 + 1.7)) * amp * gust * top * top;
	}
}
"""

const GROUND_SHADER := """
shader_type canvas_item;

// Paso de la grilla del atlas de suelo y fila del agua (WorldTiles.Ground.WATER).
uniform vec2 stride = vec2(260.0, 132.0);
uniform float water_row = 4.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	if (abs(floor(px.y / stride.y) - water_row) < 0.5) {
		// Ondas que se cruzan; donde coinciden sus crestas, un brillo.
		vec2 p = world * vec2(1.0, 2.0);
		float a = sin(p.x * 0.09 + p.y * 0.05 + TIME * 1.3);
		float b = sin(p.x * -0.06 + p.y * 0.11 - TIME * 1.1);
		float c = sin((p.x + p.y) * 0.03 + TIME * 0.6);
		float glint = smoothstep(0.75, 1.0, a * b * 0.5 + 0.5 + c * 0.15);
		COLOR.rgb = COLOR.rgb * (0.94 + 0.06 * c) + vec3(0.85, 0.95, 1.0) * glint * 0.35;
	}
}
"""

## Cuánto se mece cada tipo de prop (WorldTiles.Prop), en px lógicos en la copa.
const SWAY := {
	WorldTiles.Prop.TREE: 1.8,
	WorldTiles.Prop.PINE: 1.3,
	WorldTiles.Prop.BUSH: 0.9,
}


static func props_material() -> ShaderMaterial:
	var material := _make(PROPS_SHADER)
	material.set_shader_parameter("stride", Vector2((WorldTiles.PROP_REGION + WorldTiles.ATLAS_SEPARATION) * WorldTiles.ART_SCALE))
	material.set_shader_parameter("region_height", float(WorldTiles.PROP_REGION.y * WorldTiles.ART_SCALE))
	var sway := PackedFloat32Array()
	sway.resize(10)
	for kind: int in SWAY:
		sway[kind] = SWAY[kind]
	material.set_shader_parameter("sway", sway)
	return material


static func ground_material() -> ShaderMaterial:
	var material := _make(GROUND_SHADER)
	material.set_shader_parameter("stride", Vector2((WorldTiles.TILE_SIZE + WorldTiles.ATLAS_SEPARATION) * WorldTiles.ART_SCALE))
	material.set_shader_parameter("water_row", float(WorldTiles.Ground.WATER))
	return material


static func _make(code: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = code
	return material
