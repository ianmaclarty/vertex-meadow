local save = {}

local win = require "window"

local
function do_save(old_scene, old_bg, floor, ceiling, floor_detail, ceiling_detail, terrain_state)
    floor.fb:read_back()
    ceiling.fb:read_back()
    floor_detail.fb:read_back()
    ceiling_detail.fb:read_back()
    local floor_data = am.base64_encode(am.encode_png(floor.img))
    local ceiling_data = am.base64_encode(am.encode_png(ceiling.img))
    local floor_detail_data = am.base64_encode(am.encode_png(floor_detail.img))
    local ceiling_detail_data = am.base64_encode(am.encode_png(ceiling_detail.img))
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
        links = links,
    }
    local data = {
        ["floor.png64"] = floor_data,
        ["ceiling.png64"] = ceiling_data,
        ["floor_detail.png64"] = floor_detail_data,
        ["ceiling_detail.png64"] = ceiling_detail_data,
        ["settings.lua"] = "return "..table.tostring(settings, 2),
    }
    local json = am.to_json(data);
    am.eval_js("localStorage.setItem('vertex_meadow_save', JSON.stringify("..am.to_json(data).."));");
    win.scene = old_scene
    win.clear_color = old_bg
end

function save.save(floor, ceiling, floor_detail, ceiling_detail, terrain_state)
    local please_wait = am.translate(win.left + win.width/2, win.bottom + win.height/2) ^ am.scale(2) ^ am.text("SAVING... PLEASE WAIT", "center", "center")
    local old_scene = win.scene
    local old_bg = win.clear_color
    win.clear_color = vec4(0, 0, 0, 1)
    win.scene = please_wait
    win.scene:action(function()
        do_save(old_scene, old_bg, floor, ceiling, floor_detail, ceiling_detail, terrain_state)
        return true
    end)
end

function save.is_save()
    return am.eval_js("localStorage.getItem('vertex_meadow_save') ? true : false;");
end

function save.load_save(start)
    local loading = am.translate(win.left + win.width/2, win.bottom + win.height/2) ^ am.scale(2) ^ am.text("LOADING... PLEASE WAIT", "center", "center")
    win.scene = loading
    win.clear_color = vec4(0, 0, 0, 1)
    local data = am.eval_js("JSON.parse(localStorage.getItem('vertex_meadow_save'))");
    local
    function extract_img(name)
        local base64 = data[name..".png64"]
        local buf = am.base64_decode(base64)
        local img = am.decode_png(buf)
        local tex = am.texture2d{
            image = img,
            swrap = "mirrored_repeat",
            twrap = "mirrored_repeat",
            format = "rgba",
            minfilter = "linear",
            magfilter = "linear",
        }
        return {
            tex = tex,
            img = img,
            fb = am.framebuffer(tex)
        }
    end
    local floor = extract_img"floor"
    local floor_detail = extract_img"floor_detail"
    local ceiling = extract_img"ceiling"
    local ceiling_detail = extract_img"ceiling_detail"
    local settings = assert(loadstring(data["settings.lua"]))()
    settings.floor_texture = floor.tex
    settings.ceiling_texture = ceiling.tex
    settings.floor_detail_texture = floor_detail.tex
    settings.ceiling_detail_texture = ceiling_detail.tex
    start(floor, floor_detail, ceiling, ceiling_detail, settings)
end

return save
