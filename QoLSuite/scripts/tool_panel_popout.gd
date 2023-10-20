var editor
var tools
var tool_panel_to_popout_window: Dictionary = {}
var opened_tool_name
var active_tool_name
var tool_focus_accepted: bool = false
var current_tool_panel

func _init(editor: CanvasLayer, input_event_emitter):
    self.editor = editor
    self.tools = editor.get_node("VPartition/Panels/Tools")
    opened_tool_name = editor.ActiveToolName
    active_tool_name = editor.ActiveToolName
    input_event_emitter.connect("signal_input", self, "tools_input")
    #for tool_bar in editor.Toolset.anchor.get_children():
    #    if not "ToolsetButton" in tool_bar or tool_bar.Title == "Select" or tool_bar.Title == "Prefabs":
    #        continue
    for tool_bar in editor.Toolset.Toolbars.values():
        var popout_button: Button = Button.new()
        popout_button.icon = load("res://ui/icons/misc/unanchored.png")
        #popout_button.anchor_left = 1
        #popout_button.anchor_top = 1
        #popout_button.anchor_right = 1
        #popout_button.anchor_bottom = 1
        #popout_button.margin_left = -20
        popout_button.connect("pressed", self, "popout_button_pressed", [tool_bar])

        tool_bar.add_child_below_node(tool_bar.get_node("Spacer"), popout_button)

func update(_delta):
    tool_focus_accepted = false

func obtain_tool_focus() -> bool:
    if tool_focus_accepted:
        return false
    else:
        tool_focus_accepted = true
        return true

func popout_button_pressed(tool_bar: VBoxContainer):
    for tool_panel in tool_bar.divider.get_children():
        if not tool_panel in tool_bar.panels.values():
            continue
        if tool_panel in tool_panel_to_popout_window:
            continue
        if not tool_panel.visible:
            continue
        var panel_index: int = tool_bar.panels.values().find(tool_panel)
        var popout_window: PopoutWindow = PopoutWindow.new(self, tool_bar.Title if tool_bar.ForceTool != null else tool_bar.buttons[panel_index].Label, editor, tool_panel, tool_bar.panels.keys()[panel_index], tool_bar.divider)
        tool_panel_to_popout_window[tool_panel] = popout_window
        break

func tool_panel_from_name(tool_name: String):
    return null if tool_name == null else editor.Toolset.ToolPanels[tool_name]

func closed(tool_panel, tool_name: String):
    tool_panel_to_popout_window.erase(tool_panel)
    if opened_tool_name == tool_name or active_tool_name != tool_name:
        return
    current_tool_panel = tool_panel_from_name(opened_tool_name)
    active_tool_name = opened_tool_name
    tool_panel.Hide()
    if opened_tool_name != null:
        editor.Toolset.Quickswitch(opened_tool_name)
    else:
        editor.OnDeselectTool()

func tools_input(event: InputEvent, _emitter):
    if not event is InputEventMouseButton or (event.button_index != BUTTON_LEFT and event.button_index != BUTTON_RIGHT):
        return
    if event.position.x < tools.rect_position.x or event.position.y < tools.rect_position.y or event.position.x > tools.rect_position.x + tools.rect_size.x or event.position.y > tools.rect_position.y + tools.rect_size.y:
        return
    if not obtain_tool_focus():
        return
    if opened_tool_name != null and editor.ActiveToolName != opened_tool_name:
        update_active_tool(tool_panel_from_name(opened_tool_name), opened_tool_name)
        editor.Toolset.Quickswitch(opened_tool_name)
    yield(editor.get_tree(), "idle_frame")
    if editor.ActiveToolName == active_tool_name or editor.ActiveToolName == opened_tool_name:
        return
    update_active_tool(tool_panel_from_name(editor.ActiveToolName), editor.ActiveToolName)
    opened_tool_name = editor.ActiveToolName
    if opened_tool_name != null:
        editor.Toolset.Quickswitch(opened_tool_name)

func update_active_tool(tool_panel, tool_name: String):
    if current_tool_panel != null && current_tool_panel.visible:
        current_tool_panel.Hide()
        current_tool_panel.show()
    current_tool_panel = tool_panel
    active_tool_name = tool_name

class PopoutWindow:
    extends WindowDialog

    var popout_handler
    var editor
    var tool_panel
    var tool_name: String
    var content: Control = Control.new()
    var divider
    var original_size: Vector2
    var collapsed_size: Vector2

    func _init(popout_handler, window_title, editor, tool_panel, tool_name: String, divider):
        self.popout_handler = popout_handler
        self.editor = editor
        self.tool_panel = tool_panel
        self.tool_name = tool_name
        self.divider = divider
        divider.remove_child(tool_panel)
        add_child(content)
        content.add_child(tool_panel)

        popup_exclusive = true
        var last_element: Control = tool_panel.Align.get_children().back()
        rect_size = Vector2(tool_panel.rect_size.x, last_element.rect_position.y + last_element.rect_size.y + 4)
        original_size = rect_size
        collapsed_size = Vector2(rect_size.x, 0)
        rect_position = Vector2(100, 50)
        self.window_title = window_title
        
        # default pos is Vector(52, 0)
        tool_panel.rect_position = Vector2(0, 0)
        editor.windowsNode.add_child(self)

        tool_panel.connect("visibility_changed", self, "handle_tool_panel_visibility")

        show()

    func _input(event: InputEvent):
        if not event is InputEventMouseButton or (event.button_index != BUTTON_LEFT and event.button_index != BUTTON_RIGHT):
            return
        if event.position.x < rect_position.x or event.position.y < rect_position.y - 28 or event.position.x > rect_position.x + rect_size.x or event.position.y > rect_position.y + rect_size.y:
            return
        if not popout_handler.obtain_tool_focus():
            return
        if event.position.y < rect_position.y:
            editor.windowsNode.move_child(self, editor.windowsNode.get_children().size() - 1)
            if event.doubleclick:
                content.visible = not content.visible
                if content.visible:
                    rect_size = original_size
                else:
                    rect_size = collapsed_size
            return
        if not content.visible:
            return
        if editor.ActiveTool == tool_panel.Tool:
            return
        editor.OnSelectTool(tool_name)
        popout_handler.update_active_tool(tool_panel, tool_name)
        tool_panel.Show()
        editor.windowsNode.move_child(self, editor.windowsNode.get_children().size() - 1)
    
    func _gui_input(event: InputEvent):
        if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and not event.pressed:
            var x: float = clamp(rect_position.x, 0, get_viewport().size.x - rect_size.x)
            var y: float = clamp(rect_position.y, 28, get_viewport().size.y)
            if x != rect_position.x or y != rect_position.y:
                rect_position = Vector2(x, y)
    
    func _closed():
        content.remove_child(tool_panel)
        tool_panel.rect_position = Vector2(52, 0)
        divider.add_child(tool_panel)
        tool_panel.disconnect("visibility_changed", self, "handle_tool_panel_visibility")
        popout_handler.closed(tool_panel, tool_name)
        queue_free()
    
    func handle_tool_panel_visibility():
        tool_panel.show()