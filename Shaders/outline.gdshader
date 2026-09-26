shader_type canvas_item;
uniform vec4 outline_color : source_color = vec4(1.0);
//Outline thickness in texture pixels; supports fractional widths so
//the ring survives linear scaling and filtering.
uniform float outline_width : hint_range(0.0, 8.0, 0.5) = 1.0;
//Blinking modulates the base color.
//Set blink_time_scale to 0 if you don't want blinking.
uniform vec4 blink_color : source_color = vec4(1.0);
uniform float blink_time_scale : hint_range(0.0, 10.0, 0.1) = 0.0;
//Alpha above this counts as sprite; tolerant to linear-filtered
//sampling where texel edges blend between 0 and 1.
const float ALPHA_EDGE = 0.5;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	bool art = texture(TEXTURE, UV).a > ALPHA_EDGE;
	//Ring: march outward in 16 directions up to outline_width texels;
	//any solid hit inside the radius puts this pixel in the ring.
	bool ring = false;
	for (int i = 0; i < 16 && !ring; i++) {
		float angle = 6.2831853 * float(i) / 16.0;
		vec2 dir = vec2(cos(angle), sin(angle));
		for (int s = 1; s <= 8 && !ring; s++) {
			if (float(s) > outline_width) {
				break;
			}
			if (texture(TEXTURE, UV + dir * px * float(s)).a > ALPHA_EDGE) {
				ring = true;
			}
		}
	}
	//Enclosed holes: march the four cardinal directions; hitting solid
	//art in all of them means this transparent pixel sits inside the
	//silhouette and fills with the outline colour.
	bool enclosed = !art;
	vec2 ray = UV;
	for (int i = 0; i < 256 && enclosed; i++) {
		ray.x += px.x;
		if (ray.x > 1.0) {
			enclosed = false;
		} else if (texture(TEXTURE, ray).a > ALPHA_EDGE) {
			break;
		}
	}
	ray = UV;
	for (int i = 0; i < 256 && enclosed; i++) {
		ray.x -= px.x;
		if (ray.x < 0.0) {
			enclosed = false;
		} else if (texture(TEXTURE, ray).a > ALPHA_EDGE) {
			break;
		}
	}
	ray = UV;
	for (int i = 0; i < 256 && enclosed; i++) {
		ray.y += px.y;
		if (ray.y > 1.0) {
			enclosed = false;
		} else if (texture(TEXTURE, ray).a > ALPHA_EDGE) {
			break;
		}
	}
	ray = UV;
	for (int i = 0; i < 256 && enclosed; i++) {
		ray.y -= px.y;
		if (ray.y < 0.0) {
			enclosed = false;
		} else if (texture(TEXTURE, ray).a > ALPHA_EDGE) {
			break;
		}
	}
	bool fill = !art && (ring || enclosed);
	COLOR = mix(COLOR, COLOR * blink_color, 0.5 - 0.5 * cos(TIME * blink_time_scale));
	COLOR = float(!fill) * COLOR + float(fill) * outline_color;
}
