// Plastic landing deformation for the clay player. Purely visual: it moves
// vertices in world space so the same field can be applied to the rolling body
// and to the face meshes riding on it, keeping them glued together.
//
// A landing presses a flat facet into the ball. The facet lives in the ball's
// own frame, so it holds while idle and rotates away as the ball rolls; the
// script remoulds it by rolling distance, never by elapsed time.
shader_type spatial;
render_mode world_vertex_coords, cull_disabled;

// Matte clay surface, mirroring the imported StandardMaterial3D.
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D normal_tex : hint_normal;
uniform float normal_scale = 1.0;
uniform sampler2D rough_tex : hint_default_white;
uniform vec4 rough_mask = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);

const int DENTS = 4;

uniform vec3 field_centre = vec3(0.0);
// Rides the deformed ball back onto the ground so it neither floats nor sinks.
uniform vec3 field_shift = vec3(0.0);
uniform float field_radius = 1.0;
// Capped blend toward the mean radius: rolling works the clay slightly smoother.
uniform float rounding = 0.0;
// xyz: facet normal in world space. w: facet distance from the centre.
uniform vec4 dent_axis[DENTS];
// x: fillet width. y: lateral bulge. z: cosine of the facet rim.
uniform vec4 dent_form[DENTS];

// Smooth min: gives the pressed facet a rounded fillet instead of a crease.
float smin(float a, float b, float k) {
	float d = max(k - abs(a - b), 0.0) / k;
	return min(a, b) - d * d * k * 0.25;
}

vec3 clay_deform(vec3 p) {
	vec3 r = p - field_centre;
	float len = length(r);
	if (len < 0.001) {
		return p + field_shift;
	}

	r = mix(r, r * (field_radius / len), rounding);
	vec3 nrm = r / len;

	for (int i = 0; i < DENTS; i++) {
		vec3 ax = dent_axis[i].xyz;
		float h = dot(r, ax);
		vec3 lat = r - h * ax;
		// Flatten only what the ground actually pressed on.
		h = smin(h, dent_axis[i].w, dent_form[i].x);
		// The clay driven out of the facet swells in a band around its rim.
		float d = dot(nrm, ax) - dent_form[i].z;
		float ll = length(lat);
		if (ll > 1e-4) {
			lat += (lat / ll) * dent_form[i].y * exp(-(d * d) / 0.0338);
		}
		r = lat + h * ax;
	}

	return field_centre + r + field_shift;
}

void vertex() {
	vec3 n0 = NORMAL;
	float hand = sign(dot(cross(n0, TANGENT), BINORMAL));

	// Rebuild the normal from the deformed surface: two tangent probes span it.
	vec3 up = abs(n0.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t1 = normalize(cross(n0, up));
	vec3 t2 = cross(n0, t1);
	const float e = 0.012;

	vec3 p0 = clay_deform(VERTEX);
	vec3 n = cross(clay_deform(VERTEX + t1 * e) - p0, clay_deform(VERTEX + t2 * e) - p0);

	VERTEX = p0;
	NORMAL = length(n) > 1e-9 ? normalize(n) : n0;

	vec3 t = TANGENT - NORMAL * dot(NORMAL, TANGENT);
	if (length(t) > 1e-5) {
		TANGENT = normalize(t);
		BINORMAL = normalize(cross(NORMAL, TANGENT) * hand);
	}
}

void fragment() {
	vec2 uv = UV * uv_scale.xy + uv_offset.xy;
	ALBEDO = albedo.rgb;
	METALLIC = 0.0;
	SPECULAR = specular;
	ROUGHNESS = dot(texture(rough_tex, uv), rough_mask) * roughness;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
}
