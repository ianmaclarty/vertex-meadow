local gist = {}

local win = require "window"
local title = require "title"
local focus = require "focus"

local
function do_share(old_scene, old_bg, floor, ceiling, floor_detail, ceiling_detail, terrain_state)
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
        noclip = terrain_state.settings.noclip,
        links = links,
    }
    local req = {
        description = "Vertex Meadow Shared Level",
        public = true,
        files = {
            ["README"] = {content = "This is a Vertex Meadow shared level. Go to http://www.vertexmeadow.xyz/player.html?l=<gist id> to view it."},
            ["floor.png64"] = {content = floor_data},
            ["ceiling.png64"] = {content = ceiling_data},
            ["floor_detail.png64"] = {content = floor_detail_data},
            ["ceiling_detail.png64"] = {content = ceiling_detail_data},
            ["settings.lua"] = {content = "return "..table.tostring(settings, 2)},
        }
    }
    local json = am.to_json(req);
    local http = am.http("https://api.github.com/gists", json);
    win.scene:action(function()
        if http.status == "success" then
            local res = am.parse_json(http.response)
            am.eval_js("prompt('Share successful! The URL is:', 'http://www.vertexmeadow.xyz/player.html?l=' + '"..res.id.."');")
            win.scene = old_scene
            win.clear_color = old_bg
            focus.regain("Share successful")
            return true
        elseif http.status == "error" then
            am.eval_js("alert('Sorry, but an error occured while sharing your level (error code: ' + "..http.code.." + ').');")
            win.scene = old_scene
            win.clear_color = old_bg
            focus.regain("Share failed")
            return true
        end
        if win:key_pressed"escape" then
            win:close()
        end
    end)
end

function gist.share(floor, ceiling, floor_detail, ceiling_detail, terrain_state)
    local please_wait = am.translate(win.left + win.width/2, win.bottom + win.height/2) ^ am.scale(2) ^ am.text("SHARING... PLEASE WAIT", "center", "center")
    local old_scene = win.scene
    local old_bg = win.clear_color
    win.clear_color = vec4(0, 0, 0, 1)
    win.scene = please_wait
    win.scene:action(function()
        do_share(old_scene, old_bg, floor, ceiling, floor_detail, ceiling_detail, terrain_state)
        return true
    end)
end

function gist.get_gist_id()
    local search = am.eval_js"location.search"
    if not search then
        return nil
    else
        return search:match"%Wl=(%w+)"
    end
end

function gist.load_gist(id, start)
    local loading = am.translate(win.left + win.width/2, win.bottom + win.height/2) ^ am.scale(2) ^ am.text("LOADING... PLEASE WAIT", "center", "center")
    win.scene = loading
    win.clear_color = vec4(0, 0, 0, 1)
    local http = am.http("https://api.github.com/gists/"..id)
    local files = {
        "floor.png64", 
        "floor_detail.png64", 
        "ceiling.png64", 
        "ceiling_detail.png64", 
        "settings.lua"
    }
    local data = {}
    win.scene:action(function()
        if http.status == "success" then
            local raw_reqs = {}
            local res = am.parse_json(http.response)
            for _, file in ipairs(files) do
                if res.files[file].truncated then
                    local raw_http = am.http(res.files[file].raw_url)
                    win.scene:action(function()
                        if raw_http.status == "success" then
                            data[file] = raw_http.response
                            return true
                        elseif raw_http.status == "error" then
                            am.eval_js("alert('Sorry, but an error occured while loading file "..file..
                                " (error code: "..raw_http.code.."').');")
                            return true
                        end
                    end)
                else
                    data[file] = res.files[file].content
                end
            end
            local function all_loaded()
                for _, file in ipairs(files) do
                    if not data[file] then
                        return false
                    end
                end
                return true
            end
            win.scene:action(function()
                if all_loaded() then
                    local
                    function extract_img(file)
                        local base64 = data[file]
                        local buf = am.base64_decode(base64)
                        local img = am.decode_png(buf)
                        local tex = am.texture2d(img)
                        tex.wrap = "mirrored_repeat"
                        tex.filter = "linear"
                        return {
                            tex = tex,
                            img = img,
                            fb = am.framebuffer(tex)
                        }
                    end
                    local floor = extract_img"floor.png64"
                    local floor_detail = extract_img"floor_detail.png64"
                    local ceiling = extract_img"ceiling.png64"
                    local ceiling_detail = extract_img"ceiling_detail.png64"
                    local settings = assert(loadstring(data["settings.lua"]))()
                    settings.floor_texture = floor.tex
                    settings.ceiling_texture = ceiling.tex
                    settings.floor_detail_texture = floor_detail.tex
                    settings.ceiling_detail_texture = ceiling_detail.tex
                    start(floor, floor_detail, ceiling, ceiling_detail, settings)
                    return true
                end
            end)
            return true
        elseif http.status == "error" then
            am.eval_js("alert('Sorry, but an error occured while loading this level (error code: "..http.code.."').');")
            return true
        end
        if win:key_pressed"escape" then
            win:close()
        end
    end)
end

return gist
