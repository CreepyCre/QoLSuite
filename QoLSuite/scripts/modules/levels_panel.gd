class_name LevelsPanel

const CLASS_NAME: String = "LevelsPanel"
const NONE_MODULATE: Color = Color(1, 1, 1, 1)

var world: Node2D
var bounds_rid: RID
var editor: CanvasLayer
var master_node: Node

var world_viewport: Viewport
var world_viewport_rid: RID
var root_viewport: Viewport
var root_viewport_rid: RID
var levels_window
var levels_tree: Tree
var level_settings
var level_settings_tree: Tree

var canvas_layer: CanvasLayer = CanvasLayer.new()
var back_buffer: BackBufferCopy = BackBufferCopy.new()
var mesh: MeshInstance2D = MeshInstance2D.new()

var buffer_viewport: Viewport = Viewport.new()
var buffer_mesh: MeshInstance2D = MeshInstance2D.new()

var menu_align
var view_button

var shader: Shader

func _init(loader, world: Node2D, editor: CanvasLayer, master_node: Node):
    self.world = world
    self.bounds_rid = world.get_node("Bounds").get_canvas_item()
    self.editor = editor
    self.master_node = master_node

    # load levels tree
    levels_window = loader.load_scene("LevelsWindow").instance()
    var v_box = levels_window.get_node("VBoxContainer")
    levels_window.connect("resized", self, "levels_window_size_changed", [levels_window, v_box])
    levels_window.connect("gui_input", self, "levels_window_gui_input", [levels_window])
    levels_tree = v_box.get_node("LevelsTree")
    levels_tree.set_script(loader.load_script("ui/levels_tree"))
    level_settings = editor.Tools["LevelSettings"]
    level_settings_tree = level_settings.tree
    levels_tree.re_init(loader, world, level_settings, funcref(self, "generate_frame_of_level"))

    # setup buttons
    var buttons_h_box: HBoxContainer = v_box.get_node("PanelContainer/HBoxContainer")
    buttons_h_box.get_node("Create").connect("pressed", self, "on_create_button")
    buttons_h_box.get_node("Delete").connect("pressed", self, "on_delete_button")
    buttons_h_box.get_node("Duplicate").connect("pressed", self, "on_duplicate_button")

    # add the panel to the windows node
    editor.windowsNode.add_child(levels_window)
    editor.Windows["Levels"] = levels_window
    levels_window.show()

    # hide unnecessary vanilla buttons
    var floatbar_align: HBoxContainer = editor.get_node("Floatbar/Floatbar/Align")
    floatbar_align.get_node("LevelOptions").hide()
    floatbar_align.get_node("CompareToggle").hide()

    # TODO: move into _Lib
    # set up view menu bar dropdown
    menu_align = editor.get_node("VPartition/MenuBar/MenuAlign")
    var menu_button = menu_align.get_node("MenuButton")
    view_button = MenuButton.new()
    view_button.text = "View"
    view_button.icon = loader.load_icon("view.png")
    view_button.flat = false
    view_button.get_popup().add_item("Levels")
    view_button.get_popup().connect("id_pressed", self, "view_id_pressed")
    menu_align.add_child_below_node(menu_button, view_button)

    # disable render loop, we will run our own
    VisualServer.render_loop_enabled = false
    # disable world viewport from always rendering
    world_viewport = master_node.Viewport
    world_viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
    world_viewport_rid = world_viewport.get_viewport_rid()
    # temporarily disable world viewport to force render order
    VisualServer.viewport_set_active(world_viewport_rid, false)
    # get root viewport
    root_viewport = master_node.get_viewport()
    root_viewport_rid = root_viewport.get_viewport_rid()

    # set up canvas layer to draw mesh in
    canvas_layer.layer = 10
    world.add_child(canvas_layer)
    canvas_layer.add_child(back_buffer)
    back_buffer.owner = canvas_layer

    # set up mesh
    var size: Vector2 = world_viewport.size
    var quad_mesh: QuadMesh = QuadMesh.new()
    quad_mesh.size = size
    quad_mesh.center_offset = Vector3(size.x / 2, size.y / 2, 0)
    mesh.mesh = quad_mesh
    mesh.texture = buffer_viewport.get_texture()
    mesh.material = ShaderMaterial.new()
    shader = loader._load("shaders/ModulateMesh.shader")
    mesh.material.shader = shader

    canvas_layer.add_child(mesh)
    mesh.owner = canvas_layer

    # set up buffer viewport
    buffer_viewport.transparent_bg = true
    buffer_viewport.size = size
    buffer_viewport.usage = Viewport.USAGE_2D
    buffer_viewport.disable_3d = true
    buffer_viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
    master_node.add_child(buffer_viewport)
    buffer_viewport.owner = master_node

    # set up buffer mesh
    buffer_mesh.size = size
    buffer_mesh.mesh = quad_mesh
    buffer_mesh.texture = world_viewport.get_texture()
    buffer_mesh.material = CanvasItemMaterial.new()
    buffer_mesh.material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA

    buffer_viewport.add_child(buffer_mesh)
    buffer_mesh.owner = buffer_viewport

    # reactivate world viewport after bugger viewport has been added to scene, this ensures render order
    VisualServer.viewport_set_active(world_viewport_rid, true)
    
    # set up level tree items
    for level in world.AllLevels:
        levels_tree.create_level_item(level, false)

    # connect to world tree node added
    master_node.get_tree().connect("node_added", self, "scene_tree_node_added")
    # connect to GridMesh hide
    world.GridMesh.connect("hide", self, "update_grid_mesh", [world.GridMesh])
    

    render_loop()

func update_grid_mesh(grid_mesh):
    grid_mesh.update()

func render_loop():
    while true:
        # ensure levels tree is up2date
        levels_tree._update()
        # reset level visibility
        for level in world.AllLevels:
            level.show()
            level.Lights.hide()
            VisualServer.canvas_item_set_visible(level.get_canvas_item(), false)
        
        # draw grid, bounds and blank background
        VisualServer.canvas_item_set_visible(world.GridMesh.get_canvas_item(), true)
        VisualServer.canvas_item_set_visible(bounds_rid, true)
        VisualServer.canvas_item_set_visible(mesh.get_canvas_item(), false)
        VisualServer.viewport_set_update_mode(world_viewport_rid, VisualServer.VIEWPORT_UPDATE_ONCE)
        
        if (levels_tree.preview_level != null):
            VisualServer.canvas_item_set_visible(levels_tree.preview_level.get_canvas_item(), true)
            # draw to screen
            VisualServer.force_draw()
            VisualServer.canvas_item_set_visible(levels_tree.preview_level.get_canvas_item(), false)
        else:
            # collect visible levels
            var items: Array = []
            var it: TreeItem = levels_tree.get_root().get_children()
            while it != null:
                if (levels_tree.is_level_visible(it)):
                    items.append(it)
                it = it.get_next()
            if (not items.empty()):
                VisualServer.force_draw(false)
                # hide grid and bounds
                VisualServer.canvas_item_set_visible(world.GridMesh.get_canvas_item(), false)
                VisualServer.canvas_item_set_visible(bounds_rid, false)
                VisualServer.canvas_item_set_visible(mesh.get_canvas_item(), true)
            for item in items:
                var level: Node2D = item.get_meta("level")
                VisualServer.canvas_item_set_modulate(mesh.get_canvas_item(), levels_tree.alpha_color(item))
                VisualServer.canvas_item_set_visible(level.get_canvas_item(), true)
                VisualServer.viewport_set_update_mode(buffer_viewport.get_viewport_rid(), VisualServer.VIEWPORT_UPDATE_ONCE)
                VisualServer.viewport_set_update_mode(world_viewport_rid, VisualServer.VIEWPORT_UPDATE_ONCE)
                level.Lights.show()
                VisualServer.force_draw(false)
                VisualServer.canvas_item_set_visible(level.get_canvas_item(), false)
                level.Lights.hide()

            # draw to screen
            VisualServer.force_draw()
        # wait until next frame
        yield(editor.get_tree(), "idle_frame")

func generate_frame_of_level(level: Node2D) -> ImageTexture:
    # hide grid, bounds and mesh
    VisualServer.canvas_item_set_visible(world.GridMesh.get_canvas_item(), false)
    VisualServer.canvas_item_set_visible(bounds_rid, false)
    VisualServer.canvas_item_set_visible(mesh.get_canvas_item(), false)
    
    # draw level
    VisualServer.canvas_item_set_visible(level.get_canvas_item(), true)
    VisualServer.viewport_set_update_mode(world_viewport_rid, VisualServer.VIEWPORT_UPDATE_ONCE)
    level.Lights.show()
    VisualServer.force_draw(false)
    VisualServer.canvas_item_set_visible(level.get_canvas_item(), false)
    level.Lights.hide()

    # get image data
    var image: Image = VisualServer.texture_get_data(VisualServer.viewport_get_texture(world_viewport_rid))
    var texture: ImageTexture = ImageTexture.new()
    texture.create_from_image(image)
    return texture


func view_id_pressed(id: int):
    match id:
        0:
            levels_window.visible = not levels_window.visible

func on_create_button():
    var level: Node2D = world.CreateLevel("auto generated")
    level.Terrain.visible = false
    level_to_level_settings_tree(level)
    
func on_delete_button():
    var level: Node2D = world.Level
    var item: TreeItem = level_settings_tree.get_root().get_children()
    while item != null:
        if item.get_meta("meta") == level:
            item.select(0)
            level_settings.DeleteLevel()
            break
        item = item.get_next()

func on_duplicate_button():
    var level: Node2D = world.CloneLevel(world.Level, "auto generated")
    level_to_level_settings_tree(level)

func level_to_level_settings_tree(level: Node2D):
    level_settings_tree.AddItemFirst("auto generated", level)
    editor.UpdateLevelOptions()
    level_settings.UpdateDeleteButton()

func scene_tree_node_added(node: Node):
    if (node in world.AllLevels):
        levels_tree.create_level_item(node, true)
    

func levels_window_size_changed(window: WindowDialog, v_box: VBoxContainer):
    v_box.rect_size = window.rect_size

func levels_window_gui_input(event: InputEvent, window: WindowDialog):
    if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and not event.pressed:
        var x: float = clamp(window.rect_position.x, 0, window.get_viewport().size.x - window.rect_size.x)
        var y: float = clamp(window.rect_position.y, 28, window.get_viewport().size.y)
        if x != window.rect_position.x or y != window.rect_position.y:
            window.rect_position = Vector2(x, y)

func unload():
    # disconnect from tree node added
    master_node.get_tree().disconnect("node_added", self, "scene_tree_node_added")
    # disconnect from GridMesh hide
    world.grid_mesh.disconnect("hide", self, "update_grid_mesh")

    var floatbar_align: HBoxContainer = editor.get_node("Floatbar/Floatbar/Align")
    floatbar_align.get_node("LevelOptions").show()
    floatbar_align.get_node("CompareToggle").show()

    menu_align.remove_child(view_button)
    view_button.free()
    editor.windowsNode.remove_child(levels_window)
    editor.Windows.erase("Levels")
    levels_window.free()

    VisualServer.render_loop_enabled = true