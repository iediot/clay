shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// Clay water: the same matte fingerprint surface as the ground, with the grain
// creeping slowly downstream and a small swell crossing it. No transparency and
// no gloss - it is a ribbon of plasticine, not a liquid.

uniform vec4 albedo : source_color = vec4(0.25, 0.58, 0.80, 1.0);
uniform sampler2D fingerprint : hint_normal;
uniform float grain = 26.0;
uniform float relief = 9.0;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.72;
uniform float flow = 0.035;
uniform float swell = 0.055;
uniform float swell_scale = 0.22;

varying vec3 world_pos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(w.x * swell_scale + TIME * 0.5) * sin(w.z * swell_scale * 1.7 - TIME * 0.31);
	VERTEX.y += wave * swell;
	world_pos = w;
}

void fragment() {
	vec2 uv = vec2(world_pos.x, world_pos.z) / grain;
	uv.x -= TIME * flow;
	vec3 n = texture(fingerprint, uv).xyz * 2.0 - 1.0;
	NORMAL_MAP = normalize(mix(vec3(0.0, 0.0, 1.0), n, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = relief;
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness_amount;
	METALLIC = 0.0;
	SPECULAR = 0.1;
}
