var script_class = "tool"

var LOGGER

var loader

# need to keep refs, otherwise the objects get yeeted
var no_update: Array = []
var with_update: Array = []

func start():
    if (not Engine.has_signal("_lib_register_mod")):
        return
    Engine.emit_signal("_lib_register_mod", self)

    LOGGER = self.Global.API.Logger

    self.Global.API.ModSignalingApi.connect("unload", self, "unload")

    loader = self.Global.API.Util.create_loading_helper()

    # Tool Panel Popout
    LOGGER.info("Loading [ToolPanelPopout]")
    with_update.append(loader.load_script("modules/tool_panel_popout").new(self.Global.Editor, self.Global.API.InputMapApi.get_or_append_event_emitter(self.Global.Editor.Toolset)))

    # Levels Panel
    LOGGER.info("Loading [LevelsPanel]")
    no_update.append(loader.load_script("modules/levels_panel").new(loader, self.Global.World, self.Global.Editor, self.Global.World.owner))

func update(delta):
    for obj in with_update:
        obj.update(delta)
    
func unload():
    for obj in no_update:
        if obj.has_method("unload"):
            obj.unload()

    for obj in with_update:
        if obj.has_method("unload"):
            obj.unload()