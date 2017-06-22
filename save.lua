local save = {}

local win = require "window"

local
function do_save(old_scene, old_bg, floor, ceiling, floor_detail, ceiling_detail, hands, terrain_state)
    local settings = {
        floor_heightmap_scale = terrain_state.settings.floor_heightmap_scale,
        ceiling_heightmap_scale = terrain_state.settings.ceiling_heightmap_scale,
        floor_detail_scale = terrain_state.settings.floor_detail_scale,
        ceiling_detail_scale = terrain_state.settings.ceiling_detail_scale,
        floor_y_scale = terrain_state.settings.floor_y_scale,
        ceiling_y_scale = terrain_state.settings.ceiling_y_scale,
        floor_y_offset = terrain_state.settings.floor_y_offset,
        ceiling_y_offset = terrain_state.settings.ceiling_y_offset,
        fog_color = terrain_state.settings.fog_color,
        fog_dist = terrain_state.settings.fog_dist,
        detail_height = terrain_state.settings.detail_height,
        ambient = terrain_state.settings.ambient,
        diffuse = terrain_state.settings.diffuse,
        emission = terrain_state.settings.emission,
        specular = terrain_state.settings.specular,
        shininess = terrain_state.settings.shininess,
        start_pos = terrain_state.settings.start_pos,
        width = terrain_state.settings.width,
        depth = terrain_state.settings.depth,
        filter = terrain_state.settings.filter,
        walk_speed = terrain_state.settings.walk_speed,
        title = terrain_state.settings.title,
        wireframe = terrain_state.settings.wireframe,
        noclip = terrain_state.settings.noclip,
        pos_internal = terrain_state.pos_internal,
        facing = terrain_state.facing,
        pitch = terrain_state.pitch,
        y_pos = terrain_state.y_pos,
    }
    local data = {
        ["settings.lua"] = "return "..table.tostring(settings, 2),
    }
    if am.platform == "html" then
        am.eval_js("localStorage.setItem('vertex_meadow_save', JSON.stringify("..am.to_json(data).."));");
    else
        local f = io.open("save.json", "w")
        f:write(am.to_json(data))
        f:close()
    end
    win.scene = old_scene
    win.clear_color = old_bg
end

function save.save(floor, ceiling, floor_detail, ceiling_detail, hands, terrain_state)
    local please_wait = am.translate(win.left + win.width/2, win.bottom + win.height/2) ^ am.scale(2) ^ am.text("SAVING... PLEASE WAIT", "center", "center")
    local old_scene = win.scene
    local old_bg = win.clear_color
    win.clear_color = vec4(0, 0, 0, 1)
    win.scene = please_wait
    win.scene:action(function()
        do_save(old_scene, old_bg, floor, ceiling, floor_detail, ceiling_detail, hands, terrain_state)
        return true
    end)
end

function save.is_save()
    if am.platform == "html" then
        return am.eval_js("localStorage.getItem('vertex_meadow_save') ? true : false;");
    else
        local f = io.open("save.json", "r")
        if f then
            f:close()
            return true
        else
            return false
        end
    end
end

function save.load_save(start, filename)
    local loading = am.translate(win.left + win.width/2, win.bottom + win.height/2) ^ am.scale(2) ^ am.text("LOADING... PLEASE WAIT", "center", "center")
    win.scene = loading
    win.clear_color = vec4(0, 0, 0, 1)
    local data
    if am.platform == "html" then
        data = am.eval_js("JSON.parse(localStorage.getItem('vertex_meadow_save'))");
    else
        filename = filename or "save.json"
        local f = io.open(filename, "r")
        data = am.parse_json(f:read("*a"))
        f:close()
    end
    local settings = assert(loadstring(data["settings.lua"]))()
    reset(settings)
end

return save
