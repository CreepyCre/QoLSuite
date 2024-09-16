class_name LevelsTree

extends Tree

const COL_DRAG = 0
const COL_PREVIEW = 1
const COL_ALPHA = 2
const COL_VISIBLE = 3

var drag: Texture

var dragged_item: TreeItem = null
var hovered_item: TreeItem = null
var selected_item: TreeItem = null

var preview_level: Node2D = null

var world: Node2D
var level_settings
var texture_provider: FuncRef

var level_to_item: Dictionary = {}

func re_init(loader, world: Node2D, level_settings, texture_provider: FuncRef):
    self.world = world
    self.level_settings = level_settings
    self.texture_provider = texture_provider

    add_icon_override("checked", loader.load_icon("eye_checked.png"))
    add_icon_override("unchecked", loader.load_icon("eye_unchecked.png"))
    drag = load("res://ui/icons/misc/drag.png")

    set_column_expand(COL_DRAG, false)
    set_column_min_width(COL_DRAG, 20)
    set_column_expand(COL_VISIBLE, false)
    set_column_min_width(COL_VISIBLE, 25)
    create_item()

    connect("item_selected", self, "_selected")
    connect("mouse_exited", self, "_mouse_exited")

func create_level_item(level: Node2D, move_top: bool = true):
    var level_tree_item: TreeItem = create_item()
    if move_top:
        level_tree_item.move_to_top()
    level_tree_item.set_meta("level", level)
    level_tree_item.set_meta("alpha", 1.0)

    level_tree_item.set_icon(COL_DRAG, null)

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

func alpha_color(item: TreeItem):
    return Color(item.get_range(COL_ALPHA) / 100.0, 1, 1, 1)

func _selected():
    if selected_item == get_selected():
        return
    select_level(get_selected())

func select_level(sel: TreeItem):
    if (selected_item != null and is_instance_valid(selected_item)):
        var prev_level: Node2D = selected_item.get_meta("level")
        if (is_instance_valid(prev_level)):
            selected_item.set_icon(COL_PREVIEW, texture_provider.call_func(prev_level))
    selected_item = sel
    var level: Node2D = selected_item.get_meta("level")

    var id: int = world.levels.find(level)
    if id < 0:
        selected_item = null
        return
    world.SetLevel(id, false)
        

func is_level_visible(item: TreeItem) -> bool:
    return item.is_checked(COL_VISIBLE) and item.get_range(COL_ALPHA) > 0

func _update():
    var item: TreeItem = level_to_item[world.Level]
    if item != selected_item:
        select_level(item)
    item = get_root().get_children()
    while item != null:
        var next = item.get_next()
        if not is_instance_valid(item.get_meta("level")):
            delete_item(item)
        item = next
    
    
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
            break

    var level: Node2D = item.get_meta("level")
    level_to_item.erase(level)
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
    if event is InputEventMouseMotion:
        var new_hovered_item: TreeItem = get_item_at_position(event.position)
        var column: int = get_column_at_position(event.position)

        if new_hovered_item != null and ((column == COL_DRAG) or (column == COL_PREVIEW)):
            preview_level = new_hovered_item.get_meta("level")
        else:
            preview_level = null

        if hovered_item == new_hovered_item:
            return
        if hovered_item != null:
            hovered_item.set_icon(COL_DRAG, null)
        hovered_item = new_hovered_item
        if hovered_item != null:
            hovered_item.set_icon(COL_DRAG, drag)
    if (event is InputEventMouseButton and event.pressed):
        var item: TreeItem = get_item_at_position(event.position)
        if (item == null):
            return
        var column: int = get_column_at_position(event.position)
        if (column != COL_ALPHA):
            return
        match event.button_index:
            BUTTON_WHEEL_UP:
                item.set_range(COL_ALPHA, clamp(item.get_range(COL_ALPHA) + 5, 0, 100))
            BUTTON_WHEEL_DOWN:
                item.set_range(COL_ALPHA, clamp(item.get_range(COL_ALPHA) - 5, 0, 100))
        

func _mouse_exited():
    if hovered_item != null:
        hovered_item.set_icon(COL_DRAG, null)
        hovered_item = null
        preview_level = null