shader_type canvas_item;
render_mode blend_premul_alpha;

void fragment() {
    vec4 screen_color = texture(SCREEN_TEXTURE, SCREEN_UV);
    vec4 mesh_color = texture(TEXTURE, UV);
    screen_color.a = screen_color.a * MODULATE.a;
    mesh_color.a = mesh_color.a * (1f - screen_color.a);
    COLOR = vec4((screen_color.rgb * screen_color.a + mesh_color.rgb * mesh_color.a) / (screen_color.a + mesh_color.a), screen_color.a + mesh_color.a);
}