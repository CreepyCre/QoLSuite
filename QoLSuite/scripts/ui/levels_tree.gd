class_name LevelsTree

extends Tree

const COL_DRAG = 0
const COL_PREVIEW = 1
const COL_ALPHA = 2
const COL_VISIBLE = 3

var busy: bool = true

var drag: Texture

var dragged_item: TreeItem = null
var hovered_item: TreeItem = null
var selected_item: TreeItem = null

var world: Node2D
var woxel_dimensions: Vector2
var level_settings

var level_to_item: Dictionary = {}

func re_init(loader, world: Node2D, level_settings):
    self.world = world
    self.woxel_dimensions = world.WoxelDimensions
    self.level_settings = level_settings

    add_icon_override("checked", loader.load_icon("eye_checked.png"))
    add_icon_override("unchecked", loader.load_icon("eye_unchecked.png"))
    drag = load("res://ui/icons/misc/drag.png")

    set_column_expand(COL_DRAG, false)
    set_column_min_width(COL_DRAG, 20)
    set_column_expand(COL_VISIBLE, false)
    set_column_min_width(COL_VISIBLE, 25)
    create_item()

    connect("item_selected", self, "_selected")
    connect("item_edited", self, "_item_edited")
    busy = false

func create_level_item(level: Node2D, mesh: MeshInstance2D, viewport: Viewport, texture: Texture, move_top: bool = true):
    busy = true

    var level_tree_item: TreeItem = create_item()
    if move_top:
        level_tree_item.move_to_top()
    level_tree_item.set_meta("level", level)
    level_tree_item.set_meta("mesh", mesh)
    level_tree_item.set_meta("viewport", viewport)
    level_tree_item.set_meta("alpha", 1.0)

    level_tree_item.set_icon(COL_DRAG, null)

    level_tree_item.set_icon(COL_PREVIEW, texture)
    level_tree_item.set_icon_max_width (COL_PREVIEW, 50)

    level_tree_item.set_cell_mode(COL_ALPHA, TreeItem.CELL_MODE_RANGE)
    level_tree_item.set_selectable(COL_ALPHA, false)
    level_tree_item.set_editable(COL_ALPHA, true)
    level_tree_item.set_range_config (COL_ALPHA, 0, 100, 5)
    level_tree_item.set_range(COL_ALPHA, 100)

    level_tree_item.set_cell_mode(COL_VISIBLE, TreeItem.CELL_MODE_CHECK)
    level_tree_item.set_selectable(COL_VISIBLE, false)
    level_tree_item.set_editable(COL_VISIBLE, true)
    level_tree_item.set_checked(COL_VISIBLE, true if world.Level == level else false)

    level_to_item[level] = level_tree_item

    level.connect("visibility_changed", self, "level_visibility_changed", [level_tree_item, level])
    busy = false

func transfer_level(level: Node2D, source: Node, target: Node):
    var current_level_id: int = world.CurrentLevelId
    var id: int = world.levels.find(level)
    if id < 0:
        return
    if id != current_level_id:
        world.SetLevel(id, false)

    prepare_level_before_exit_tree(level)
    source.remove_child(level)
    level.MeshLookup = {}
    target.add_child(level)
    if id != current_level_id:
        world.SetLevel(current_level_id, false)

func alpha_color(alpha_percentage: float):
    return Color(1, 1, 1, alpha_percentage / 100.0)

func _selected():
    if busy or selected_item == get_selected():
        return
    busy = true
    select_level(get_selected())
    busy = false

func select_level(sel: TreeItem):
    var initial_level: Node2D
    var initial_viewport: Viewport
    if selected_item != null && is_instance_valid(selected_item.get_meta("level")):
        initial_level = selected_item.get_meta("level")
        initial_viewport = selected_item.get_meta("viewport")
        if initial_level.TileMap.get_used_cells().size() > 0:
            initial_level.FloorRT.connect("tree_entered", self, "overwrite_FloorRT_size", [initial_level.FloorRT, initial_viewport.size])
            initial_level.FloorTileCamera.connect("tree_entered", self, "overwrite_floor_tile_camera",
                [initial_level.FloorTileCamera, Vector2(initial_viewport.size.x / 2, initial_viewport.size.y / 2)])
        transfer_level(initial_level, world, initial_viewport)

        var mesh: MeshInstance2D = selected_item.get_meta("mesh")
        mesh.modulate = initial_level.modulate
        initial_level.modulate = Color.white
        mesh.visible = is_level_visible(selected_item)

    selected_item = sel
    var level: Node2D = selected_item.get_meta("level")

    var id: int = world.levels.find(level)
    if id < 0:
        selected_item = null
        return
    world.SetLevel(id, false)

    prepare_level_before_exit_tree(level)
    selected_item.get_meta("viewport").remove_child(level)
    level.MeshLookup = {}
    world.add_child(level)
    # set level again to side step some bugs
    world.SetLevel(id, false)
    
    level.visible = is_level_visible(selected_item)
    var mesh: MeshInstance2D = selected_item.get_meta("mesh")
    level.modulate = mesh.modulate
    mesh.modulate = Color.white
    mesh.hide()

    # need to run the after the level has actually been switched
    if initial_viewport != null:
        initial_level.visible = true
        initial_viewport.render_target_update_mode = Viewport.UPDATE_ONCE
        call_deferred("update_once", initial_viewport)
    refresh_z_and_alpha()

func update_once(viewport: Viewport):
    yield(get_tree(), "idle_frame")
    yield(get_tree(), "idle_frame")
    viewport.render_target_update_mode = Viewport.UPDATE_ONCE

func overwrite_FloorRT_size(FloorRT: Viewport, size: Vector2):
    FloorRT.disconnect("tree_entered", self, "overwrite_FloorRT_size")
    FloorRT.size = size

func overwrite_floor_tile_camera(camera: Camera2D, position: Vector2):
    camera.disconnect("tree_entered", self, "overwrite_floor_tile_camera")
    camera.zoom = Vector2(1, 1)
    camera.position = position

func refresh_z_and_alpha():
    # collect visible level items
    var visible_items: Array = []
    var current_item: TreeItem = get_root().get_children()
    while current_item != null:
        if is_level_visible(current_item):
            visible_items.append(current_item)
        current_item = current_item.get_next()

    var z_index: int = -1
    for item in visible_items:
        if item != selected_item:
            var mesh: MeshInstance2D = item.get_meta("mesh")
            mesh.modulate = alpha_color(item.get_range(COL_ALPHA))
            mesh.z_index = z_index
            z_index -= 1
        else:
            var level: Node2D = selected_item.get_meta("level")
            level.modulate = alpha_color(item.get_range(COL_ALPHA))
            z_index -= 900
            level.z_index = z_index
            z_index -= 501

func is_level_visible(item: TreeItem) -> bool:
    return item.is_checked(COL_VISIBLE)

func level_visibility_changed(item: TreeItem, level: Node2D):
    if busy:
        return
    busy = true
    if level != world.Level:
        level.visible = true
        busy = false
        return
    var is_visible = is_level_visible(item)
    if is_visible != level.visible:
        level.visible = is_visible
    busy = false
    
func _item_edited():
    if busy:
        return
    busy = true
    var item: TreeItem = get_edited()
    var column: int = get_edited_column()
    if column == COL_VISIBLE:
        var level: Node2D = item.get_meta("level")
        if level == world.Level:
            level.visible = is_level_visible(item)
        else:
            item.get_meta("mesh").visible = is_level_visible(item)
    refresh_z_and_alpha()
    busy = false

func _process(_delta):
    if woxel_dimensions != world.WoxelDimensions:
        woxel_dimensions = world.WoxelDimensions
        for item in level_to_item.values():
            var viewport: Viewport = item.get_meta("viewport")
            var quad_mesh: QuadMesh = item.get_meta("mesh").mesh
            quad_mesh.size = woxel_dimensions
            quad_mesh.center_offset = Vector3(woxel_dimensions.x / 2, woxel_dimensions.y / 2, 0)
            viewport.size = woxel_dimensions
            if item == selected_item:
                continue
            var level: Node2D = item.get_meta("level")
            if level.TileMap.get_used_cells().size() > 0:
                overwrite_FloorRT_size(level.FloorRT, viewport.size)
                overwrite_floor_tile_camera(level.FloorTileCamera, Vector2(viewport.size.x / 2, viewport.size.y / 2))
            viewport.render_target_update_mode = Viewport.UPDATE_ONCE
            call_deferred("update_once", viewport)

    var item: TreeItem = level_to_item[world.Level]
    if item != selected_item:
        busy = true
        select_level(item)
        busy = false
    item = get_root().get_children()
    var dirty: bool = false
    while item != null:
        var next = item.get_next()
        if not is_instance_valid(item.get_meta("level")):
            busy = true
            delete_item(item)
            busy = false
            dirty = true
        item = next
    if dirty:
        refresh_z_and_alpha()
    
    
    if selected_item != null and not selected_item.is_selected(1):
        selected_item.select(1)


func delete_item(item: TreeItem):
    if item == selected_item:
        var next = item.get_next_visible(true)
        while true:
            if next == selected_item:
                selected_item = null
                break
            if not is_instance_valid(selected_item.get_meta("level")):
                continue
            selected_item = next
            var level: Node2D = selected_item.get_meta("level")

            var id: int = world.levels.find(level)
            if id < 0:
                continue
            world.SetLevel(id, false)

            prepare_level_before_exit_tree(level)
            selected_item.get_meta("viewport").remove_child(level)
            level.MeshLookup = {}
            world.add_child(level)

            # set level again to side step some bugs
            world.SetLevel(id, false)

            level.visible = is_level_visible(selected_item)
            var mesh: MeshInstance2D = selected_item.get_meta("mesh")
            level.modulate = mesh.modulate
            mesh.modulate = Color.white
            mesh.hide()

            break

    var level: Node2D = item.get_meta("level")
    level_to_item.erase(level)
    item.get_meta("mesh").queue_free()
    item.free()

func get_drag_data(position: Vector2):
    dragged_item = get_item_at_position(position)
    return dragged_item

func can_drop_data(_position, data):
    if data != dragged_item:
        return false
    drop_mode_flags = Tree.DROP_MODE_INBETWEEN + Tree.DROP_MODE_ON_ITEM
    return true

func drop_data(position, item):
    var target_item: TreeItem = get_item_at_position(position)
    if (target_item == item):
        return

    var drop_section = get_drop_section_at_position(position)
    if drop_section == -100:
        item.move_to_bottom()
        return
    
    var item_index: int = get_item_index(item)
    var target_index: int = get_item_index(target_item)
    match drop_section:
        -1:
            if target_index > item_index:
                target_index -= 1
            move_item_to_index(item, target_index)
        1:
            if target_index > item_index:
                target_index -= 1
            move_item_to_index(item, target_index + 1)
        0:
            if item_index < target_index:
                move_item_to_index(target_item, item_index)
                move_item_to_index(item, target_index)
            else:
                move_item_to_index(item, target_index)
                move_item_to_index(target_item, item_index)
    refresh_z_and_alpha()

    var tree_item: TreeItem = level_settings.tree.get_root().get_children()
    while tree_item != null:
        var next = tree_item.get_next()
        level_settings.tree.RemoveItem(tree_item)
        tree_item = next
    
    tree_item = get_root().get_children()
    while tree_item != null:
        var level: Node2D = tree_item.get_meta("level")
        level_settings.tree.AddItemLast(level.Label, level)
        tree_item = tree_item.get_next()
    level_settings.HandleTreeDragDrop()

func get_item_index(item: TreeItem) -> int:
    var current: TreeItem = get_root().get_children()
    var index: int = 0
    while current != item:
        if current == null:
            return -1
        index += 1
        current = current.get_next()
    return index

func move_item_to_index(item: TreeItem, index: int):
    item.move_to_top()
    var current_index = 0
    var items: Array = []
    var current_item = item.get_next()
    while current_index < index:
        if current_item == null:
            item.move_to_bottom()
            return
        items.append(current_item)
        current_item = current_item.get_next()
        current_index += 1
    for i in range(items.size() - 1, -1, -1):
        items[i].move_to_top()

func _gui_input(event: InputEvent):
    if not event is InputEventMouseMotion:
        return
    var new_hovered_item: TreeItem = get_item_at_position(event.position)
    if hovered_item == new_hovered_item:
        return
    if hovered_item != null:
        hovered_item.set_icon(COL_DRAG, null)
    hovered_item = new_hovered_item
    if hovered_item != null:
        hovered_item.set_icon(COL_DRAG, drag)
    
func prepare_level_before_exit_tree(level: Node2D):
    walls_tree_exiting(level.Walls)

func walls_tree_exiting(walls: Node2D):
    for wall in walls.get_children():
        var portals: Array = []
        for portal in wall.get_children():
            if not "WallDistance" in portal:
                continue
            #portal.connect("tree_exited", self, "portal_tree_exited", [portal, wall])
            wall.RemovePortal(portal)
            wall.remove_child(portal)
            portals.append(portal)
        wall.connect("tree_entered", self, "wall_tree_entered", [wall, portals])

func wall_tree_entered(wall: Node2D, portals):
    wall.disconnect("tree_entered", self, "wall_tree_entered")
    world.AssignNodeID(wall, wall.get_meta("node_id"))
    for portal in portals:
        wall.InsertPortal(portal, false)
        world.AssignNodeID(portal, portal.get_meta("node_id"))
    wall.RemakeLines()

func portal_tree_exited(portal: Node2D, wall: Node2D):
    wall.disconnect("tree_exited", self, "portal_tree_exited")
    wall.InsertPortal(portal, true)
    world.AssignNodeID(portal, portal.GetNodeID())

func _unload():
    busy = true
    var item: TreeItem = get_root().get_children()
    while item != null:
        var level: Node2D = selected_item.get_meta("level")
        var viewport: Viewport = selected_item.get_meta("viewport")
        var mesh: MeshInstance2D = selected_item.get_meta("mesh")
        if item != selected_item:
            transfer_level(level, viewport, world)
            level.visible = false
        level.modulate = Color.white
        world.remove_child(mesh)
        mesh.free()