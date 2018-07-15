local export = ...

local win = require "window"
local title = require "title"
local focus = require "focus"

local
function do_export(old_scene, old_bg, floor, ceiling, floor_detail, ceiling_detail, hands, terrain_state)
    floor.fb:read_back()
    ceiling.fb:read_back()
    floor_detail.fb:read_back()
    ceiling_detail.fb:read_back()
    if not hands.img then
        hands.img = am.image_buffer(512)
    else
        hands.fb:read_back()
    end
    local floor_data = am.base64_encode(am.encode_png(floor.img))
    local ceiling_data = am.base64_encode(am.encode_png(ceiling.img))
    local floor_detail_data = am.base64_encode(am.encode_png(floor_detail.img))
    local ceiling_detail_data = am.base64_encode(am.encode_png(ceiling_detail.img))
    local hands_data = am.base64_encode(am.encode_png(hands.img))
    local links = {}
    for _, link in ipairs(terrain_state.settings.links) do
        table.insert(links, {url = link.url, caption = link.caption, pos = link.pos})
    end
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
        links = links,
    }
    local settings_data = "return "..table.tostring(settings, 2)
    local files = {
        ["floor.png"] = floor_data,
        ["ceiling.png"] = ceiling_data,
        ["floor_detail.png"] = floor_detail_data,
        ["ceiling_detail.png"] = ceiling_detail_data,
        ["hands.png"] = hands_data,
        ["settings.lua"] = settings_data,
    }
    local json = am.to_json(files);
    am.eval_js("vm_export("..json..");");
end

function export.export(floor, ceiling, floor_detail, ceiling_detail, hands, terrain_state)
    local please_wait = am.translate(win.left + win.width/2, win.bottom + win.height/2) ^ am.scale(2) ^ am.text("EXPORTING... PLEASE WAIT", "center", "center")
    local old_scene = win.scene
    local old_bg = win.clear_color
    win.clear_color = vec4(0, 0, 0, 1)
    win.scene = please_wait
    win.scene:action(function()
        do_export(old_scene, old_bg, floor, ceiling, floor_detail, ceiling_detail, hands, terrain_state)
        win.scene = old_scene
        win.clear_color = old_bg
        return true
    end)
end
