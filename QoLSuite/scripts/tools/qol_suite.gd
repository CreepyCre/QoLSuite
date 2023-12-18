var script_class = "tool"

var loader

var world_viewport: Viewport
var world_viewport_rid: RID
var master_viewport: Viewport
var master_viewport_rid: RID
var levels_window
var levels_tree: Tree
var level_settings
var level_settings_tree: Tree

var menu_align
var view_button

var meshes_node: Node2D = Node2D.new()

# need to keep ref, otherwise the object gets yeeted
var tool_panel_popout

func start():
    if (not Engine.has_signal("_lib_register_mod")):
        return
    Engine.emit_signal("_lib_register_mod", self)

    self.Global.API.ModSignalingApi.connect("unload", self, "_unload")

    loader = self.Global.API.Util.create_loading_helper()

    # Tool Panel Popout
    tool_panel_popout = loader.load_script("tool_panel_popout").new(self.Global.Editor, self.Global.API.InputMapApi.get_or_append_event_emitter(self.Global.Editor.Toolset))

    # Levels panel stuff
    levels_window = loader.load_scene("LevelsWindow").instance()
    var v_box = levels_window.get_node("VBoxContainer")
    levels_window.connect("resized", self, "levels_window_size_changed", [levels_window, v_box])
    levels_window.connect("gui_input", self, "levels_window_gui_input", [levels_window])
    levels_tree = v_box.get_node("LevelsTree")
    levels_tree.set_script(loader.load_script("ui/levels_tree"))
    level_settings = self.Global.Editor.Tools["LevelSettings"]
    level_settings_tree = level_settings.tree
    levels_tree.re_init(loader, self.Global.World, level_settings)

    var buttons_h_box: HBoxContainer = v_box.get_node("PanelContainer/HBoxContainer")
    buttons_h_box.get_node("Create").connect("pressed", self, "on_create_button")
    buttons_h_box.get_node("Delete").connect("pressed", self, "on_delete_button")
    buttons_h_box.get_node("Duplicate").connect("pressed", self, "on_duplicate_button")

    self.Global.Editor.windowsNode.add_child(levels_window)
    self.Global.Editor.Windows["Levels"] = levels_window
    levels_window.show()

    var floatbar_align: HBoxContainer = self.Global.Editor.get_node("Floatbar/Floatbar/Align")
    floatbar_align.get_node("LevelOptions").hide()
    floatbar_align.get_node("CompareToggle").hide()

    # TODO: move into _Lib
    menu_align = self.Global.Editor.get_node("VPartition/MenuBar/MenuAlign")
    var menu_button = menu_align.get_node("MenuButton")
    view_button = MenuButton.new()
    view_button.text = "View"
    view_button.icon = loader.load_icon("view.png")
    view_button.flat = false
    view_button.get_popup().add_item("Levels")
    view_button.get_popup().connect("id_pressed", self, "view_id_pressed")
    menu_align.add_child_below_node(menu_button, view_button)

    VisualServer.render_loop_enabled = false
    self.Global.World.owner.ViewportContainer2D.visible = false
    self.Global.World.get_node("Bounds").color = Color8(255, 255, 255, 100)
    world_viewport = self.Global.World.owner.Viewport
    world_viewport.connect("size_changed", self, "on_viewport_size_changed")
    world_viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
    #world_viewport.transparent_bg = true
    #world_viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ALWAYS
    world_viewport.hdr = false
    world_viewport.disable_3d = true
    world_viewport.usage = Viewport.USAGE_2D
    world_viewport.fxaa = true
    world_viewport_rid = world_viewport.get_viewport_rid()
    master_viewport = self.Global.World.owner.get_viewport()
    master_viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
    #master_viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ALWAYS
    master_viewport_rid = master_viewport.get_viewport_rid()

    self.Global.World.owner.add_child(meshes_node)
    meshes_node.owner = self.Global.World.owner
    
    for level in self.Global.World.levels:
        prepare_level_mesh(level, false)

    self.Global.World.get_tree().connect("node_added", self, "scene_tree_node_added")






func update(_delta):
    tool_panel_popout.update()
    # draw each visible level separately storing the texture
    levels_tree._update()
    for level in self.Global.World.AllLevels:
        VisualServer.canvas_item_set_visible(level.get_canvas_item(), false)
    
    var item: TreeItem = levels_tree.get_root().get_children()
    while item != null:
        var level: Node2D = item.get_meta("level")
        if (not levels_tree.is_level_visible(item)):
            item = item.get_next()
            continue
        VisualServer.canvas_item_set_visible(level.get_canvas_item(), true)
        VisualServer.viewport_set_update_mode(world_viewport_rid, VisualServer.VIEWPORT_UPDATE_ONCE)
        VisualServer.force_draw(false)
        #var image: Image = VisualServer.texture_get_data(VisualServer.viewport_get_texture(world_viewport_rid))
        #VisualServer.texture_set_data(item.get_meta("mesh").texture.get_rid(), image)
        #VisualServer.canvas_item_set_visible(item.get_meta("mesh").get_canvas_item(), true)
        VisualServer.canvas_item_set_visible(level.get_canvas_item(), false)
        item = item.get_next()
    # draw UI and level meshes
    VisualServer.viewport_set_update_mode(master_viewport_rid, VisualServer.VIEWPORT_UPDATE_ONCE)
    VisualServer.force_draw()

func on_viewport_size_changed():
    pass # TODO

func view_id_pressed(id: int):
    match id:
        0:
            levels_window.visible = not levels_window.visible

func on_create_button():
    var level: Node2D = self.Global.World.CreateLevel("auto generated")
    level.Terrain.visible = false
    level_to_level_settings_tree(level)
    
func on_delete_button():
    var level: Node2D = self.Global.World.Level
    var item: TreeItem = level_settings_tree.get_root().get_children()
    while item != null:
        if item.get_meta("meta") == level:
            item.select(0)
            level_settings.DeleteLevel()
            break
        item = item.get_next()

func on_duplicate_button():
    var level: Node2D = self.Global.World.CloneLevel(self.Global.World.Level, "auto generated")
    level_to_level_settings_tree(level)

func level_to_level_settings_tree(level: Node2D):
    level_settings_tree.AddItemFirst("auto generated", level)
    self.Global.Editor.UpdateLevelOptions()
    level_settings.UpdateDeleteButton()

func scene_tree_node_added(node: Node):
    if ((not node.get_parent() == self.Global.World) or (not "floorRTPath" in node) or (not node is Node2D)):
        return
    prepare_level_mesh(node)

func prepare_level_mesh(level: Node2D, move_top: bool = true):


    var size: Vector2 = world_viewport.size
    var mesh = MeshInstance2D.new()
    var quad_mesh: QuadMesh = QuadMesh.new()
    quad_mesh.size = size
    quad_mesh.center_offset = Vector3(size.x / 2, size.y / 2, 0)
    quad_mesh.material = load("res://materials/Unlit.material")
    mesh.mesh = quad_mesh

    #mesh.material_override.flags_transparent = true
    #mesh.visible = false

    meshes_node.add_child(mesh)
    mesh.owner = meshes_node

    #self.Global.World.add_child(mesh)
    #mesh.owner = self.Global.World

    #var viewport: Viewport = Viewport.new()
    #var texture: Texture = viewport.get_texture()
    #mesh.texture = texture
    #mesh.add_child(viewport)
    #viewport.owner = mesh
    #viewport.size = size
    #viewport.transparent_bg = true
    #viewport.hdr = false
    #viewport.disable_3d = true
    #viewport.usage = Viewport.USAGE_2D
    #viewport.fxaa = true


    VisualServer.canvas_item_set_visible(level.get_canvas_item(), true)
    VisualServer.viewport_set_update_mode(world_viewport_rid, VisualServer.VIEWPORT_UPDATE_ONCE)
    VisualServer.force_draw(false)
    #var texture: ImageTexture = ImageTexture.new()
    #var image: Image = VisualServer.texture_get_data(VisualServer.viewport_get_texture(world_viewport_rid))
    #texture.create_from_image(image)
    #texture.resource_local_to_scene = true
    mesh.texture = world_viewport.get_texture()
    VisualServer.canvas_item_set_visible(level.get_canvas_item(), false)

    levels_tree.create_level_item(level, mesh, move_top)

func levels_window_size_changed(window: WindowDialog, v_box: VBoxContainer):
    v_box.rect_size = window.rect_size

func levels_window_gui_input(event: InputEvent, window: WindowDialog):
    if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and not event.pressed:
        var x: float = clamp(window.rect_position.x, 0, window.get_viewport().size.x - window.rect_size.x)
        var y: float = clamp(window.rect_position.y, 28, window.get_viewport().size.y)
        if x != window.rect_position.x or y != window.rect_position.y:
            window.rect_position = Vector2(x, y)
    

func _unload():
    world_viewport.disconnect("size_changed", self, "on_viewport_size_changed")

    var floatbar_align: HBoxContainer = self.Global.Editor.get_node("Floatbar/Floatbar/Align")
    floatbar_align.get_node("LevelOptions").show()
    floatbar_align.get_node("CompareToggle").show()

    menu_align.remove_child(view_button)
    view_button.free()
    self.Global.Editor.windowsNode.remove_child(levels_window)
    self.Global.Editor.Windows.erase("Levels")
    levels_tree._unload()
    levels_window.free()