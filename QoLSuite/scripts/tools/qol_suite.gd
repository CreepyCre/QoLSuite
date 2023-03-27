var script_class = "tool"

var loader
var levels_window
var levels_tree: Tree
var level_settings
var level_settings_tree: Tree

var menu_align
var view_button

func start():
    if (not Engine.has_signal("_lib_register_mod")):
        return
    Engine.emit_signal("_lib_register_mod", self)

    self.Global.API.ModSignalingApi.connect("unload", self, "_unload")

    loader = self.Global.API.Util.create_loading_helper(self.Global.Root + "../../")
    levels_window = loader.load_scene("LevelsWindow").instance()
    var v_box = levels_window.get_node("VBoxContainer")
    levels_window.connect("resized", self, "levels_window_size_changed", [levels_window, v_box])
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

    for level in self.Global.World.levels:
        level_into_viewport(level, false)

    self.Global.World.get_tree().connect("node_added", self, "scene_tree_node_added")

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
    if (not node.get_parent() == self.Global.World) or (not "floorRTPath" in node) or (not node is Node2D) or (node.has_meta("has_been_viewported")):
        return
    call_deferred("level_into_viewport", node)

func level_into_viewport(level: Node2D, move_top: bool = true):
    level.set_meta("has_been_viewported", true)

    level.CaveMesh.connect("tree_entered", self, "cave_mesh_tree_entered", [level.CaveMesh])
    level.Objects.connect("tree_entered", self, "objects_tree_entered", [level.Objects])

    var size: Vector2 = self.Global.World.WoxelDimensions
    var mesh = MeshInstance2D.new()
    var quad_mesh: QuadMesh = QuadMesh.new()
    quad_mesh.size = size
    quad_mesh.center_offset = Vector3(size.x / 2, size.y / 2, 0)
    mesh.mesh = quad_mesh
    self.Global.World.add_child_below_node(level, mesh)
    mesh.owner = self.Global.World

    var viewport: Viewport = Viewport.new()
    var texture: Texture = viewport.get_texture()
    mesh.texture = texture
    mesh.add_child(viewport)
    viewport.owner = mesh
    # maybe make this a low res option down the line
    #viewport.size = Vector2(size.x / 2, size.y / 2)
    #viewport.global_canvas_transform = viewport.global_canvas_transform.scaled(Vector2(0.5, 0.5))
    viewport.size = size
    viewport.transparent_bg = true
    viewport.hdr = false
    viewport.disable_3d = true
    viewport.usage = Viewport.USAGE_2D
    viewport.fxaa = true

    

    levels_tree.transfer_level(level, self.Global.World, viewport)
    levels_tree.create_level_item(level, mesh, viewport, texture, move_top)

    viewport.render_target_update_mode = Viewport.UPDATE_ONCE

func cave_mesh_tree_entered(cave_mesh: MeshInstance2D):
    cave_mesh.remove_child(cave_mesh.entranceWidget)
    cave_mesh.entranceWidget = cave_mesh.get_child(0)

func objects_tree_entered(objects: Node2D):
    for prop in objects.get_children():
        objects.AddToSearchTable(prop, false)
        prop.connect("tree_entered", self, "prop_tree_entered", [prop, prop.shadow, prop.Sprite])

func prop_tree_entered(prop, shadow, sprite):
    prop.disconnect("tree_entered", self, "prop_tree_entered")
    prop.shadow = shadow
    prop.Sprite = sprite
    for child in prop.get_children():
        if child != shadow and child != sprite:
            prop.remove_child(child)
            child.queue_free()

func levels_window_size_changed(window: WindowDialog, v_box: VBoxContainer):
    v_box.rect_size = window.rect_size

func _unload():
    var floatbar_align: HBoxContainer = self.Global.Editor.get_node("Floatbar/Floatbar/Align")
    floatbar_align.get_node("LevelOptions").show()
    floatbar_align.get_node("CompareToggle").show()

    menu_align.remove_child(view_button)
    view_button.free()
    self.Global.Editor.windowsNode.remove_child(levels_window)
    self.Global.Editor.Windows.erase("Levels")
    levels_tree._unload()
    levels_window.free()