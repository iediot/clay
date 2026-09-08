shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;

// The sky is one colour of clay, and it has to stay one colour. Lit normally,
// the dome's own lumps and the scene's directional light shaded it across the
// frame and it read as a gradient of several blues. So it is unshaded — no
// scene light touches it — and all of its relief comes from this shader: a
// fixed light direction driving a narrow brightness band around the single
// colour, wide enough that the thumbed lumps and the fingerprint read, narrow
// enough that it never becomes a second colour.

uniform vec4 sky_color : source_color = vec4(0.17, 0.56, 0.88, 1.0);
uniform sampler2D fingerprint : hint_normal;
uniform float grain = 330.0;
uniform float relief : hint_range(0.0, 3.0) = 1.0;
uniform float contrast : hint_range(0.0, 0.6) = 0.15;
uniform vec3 light_dir = vec3(0.42, 0.66, 0.38);

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Triplanar, because the dome has no unwrap that would not pinch at the poles.
vec3 grain_normal(vec3 p, vec3 n) {
	vec3 b = pow(abs(n), vec3(4.0));
	b /= (b.x + b.y + b.z);
	vec3 gx = texture(fingerprint, p.zy / grain).xyz * 2.0 - 1.0;
	vec3 gy = texture(fingerprint, p.xz / grain).xyz * 2.0 - 1.0;
	vec3 gz = texture(fingerprint, p.xy / grain).xyz * 2.0 - 1.0;
	return gx * b.x + gy * b.y + gz * b.z;
}

void fragment() {
	vec3 n = normalize(w_nrm + grain_normal(w_pos, w_nrm) * relief);
	float s = dot(n, normalize(light_dir)) * 0.5 + 0.5;
	ALBEDO = sky_color.rgb * mix(1.0 - contrast, 1.0 + contrast, s);
}
