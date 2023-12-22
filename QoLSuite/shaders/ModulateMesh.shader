shader_type canvas_item;
render_mode blend_disabled;

void fragment() {
    vec4 mesh_color = texture(TEXTURE, UV);
    vec4 screen_color = texture(SCREEN_TEXTURE, SCREEN_UV);
    screen_color.a *= MODULATE.r * (1f - mesh_color.a);
    COLOR = vec4((screen_color.rgb * screen_color.a + mesh_color.rgb * mesh_color.a) / (screen_color.a + mesh_color.a), screen_color.a + mesh_color.a);
}