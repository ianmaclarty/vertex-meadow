local editor = ...

local win = require "window"
local sprites = require "sprites"
local mouse = require "mouse"
local gist = require "gist"
local save = require "save"
local help = require "help"
local focus = require "focus"
local download = require "download"
local upload = require "upload"

local label_w = 64
local val_w = 32

local num_brushes = 0
local brush_sprite_specs = {}
while sprites["brush"..(num_brushes + 1)] do
    num_brushes = num_brushes + 1
    brush_sprite_specs[num_brushes] = sprites["brush"..(num_brushes)]
end
local webcam_tex = am.texture2d(512)
num_brushes = num_brushes + 1
local webcam_brush = num_brushes
brush_sprite_specs[num_brushes] = {
    texture = webcam_tex,
    x1 = 0,
    y1 = 0,
    x2 = 256,
    y2 = 256,
    s1 = 0,
    t1 = 1,
    s2 = 1,
    t2 = 0,
    width = 256,
    height = 256,
}

local heightmap_vshader = [[
    precision highp float;
    uniform mat4 P;
    uniform mat4 MV;
    attribute vec2 vert;
    attribute vec2 uv;
    varying vec2 v_uv;
    void main() {
        v_uv = uv;
        gl_Position = P * MV * vec4(vert, 0.0, 1.0);
    }
]]

local heightmap_fshader = [[
    precision mediump float;
    uniform sampler2D tex;
    uniform vec4 height_src;
    varying vec2 v_uv;
    void main() {
        vec4 s = texture2D(tex, v_uv) * height_src;
        float alpha = s.r + s.g + s.b + s.a;
        gl_FragColor = vec4(vec3(alpha), 1.0);
    }
]]

local color_fshader = [[
    precision mediump float;
    uniform sampler2D tex;
    varying vec2 v_uv;
    void main() {
        vec4 s = texture2D(tex, v_uv);
        gl_FragColor = vec4(s.rgb * 0.7 + s.a * 0.3, 1.0);
    }
]]

local hands_fshader = [[
    precision mediump float;
    uniform sampler2D tex;
    varying vec2 v_uv;
    void main() {
        vec4 s = texture2D(tex, v_uv);
        float checks = mod(floor(gl_FragCoord.x / 10.0) + floor(gl_FragCoord.y / 10.0), 2.0);
        gl_FragColor = vec4(mix(vec3(checks) * 0.2 + 0.4, s.rgb, s.a), 1.0);
    }
]]

local alpha_only_fshader = [[
    precision mediump float;
    uniform sampler2D tex;
    varying vec2 v_uv;
    void main() {
        vec4 s = texture2D(tex, v_uv);
        gl_FragColor = vec4(s.a);
    }
]]

local color_only_fshader = [[
    precision mediump float;
    uniform sampler2D tex;
    varying vec2 v_uv;
    void main() {
        vec4 s = texture2D(tex, v_uv);
        gl_FragColor = vec4(s.rgb, 1.0);
    }
]]

local heightmap_shader = am.program(heightmap_vshader, heightmap_fshader)
local color_shader = am.program(heightmap_vshader, color_fshader)
local hands_shader = am.program(heightmap_vshader, hands_fshader)
local alpha_only_shader = am.program(heightmap_vshader, alpha_only_fshader)
local color_only_shader = am.program(heightmap_vshader, color_only_fshader)
local capture_shader = alpha_only_shader

local draw_vshader = [[
    precision highp float;
    uniform mat4 P;
    uniform mat4 MV;
    attribute vec2 vert;
    attribute vec2 uv;
    varying vec2 v_uv;
    void main() {
        v_uv = uv;
        gl_Position = P * MV * vec4(vert, 0.0, 1.0);
    }
]]

local draw_fshader = [[
    precision mediump float;
    uniform sampler2D tex;
    uniform vec4 color;
    uniform float exp1;
    uniform float exp2;
    uniform vec4 height_src;
    varying vec2 v_uv;
    void main() {
        vec4 s = texture2D(tex, v_uv);
        vec4 v = s * height_src;
        float alpha = v.r + v.g + v.b + v.a;
        if (alpha < 1.0/255.0) discard;
        alpha = pow(1.0 - pow(1.0 - alpha, exp1), exp2) * color.a;
        gl_FragColor = vec4(s.rgb * color.rgb * color.a, alpha);
    }
]]

local draw_shader = am.program(draw_vshader, draw_fshader)

local
function in_bounds(p, b) 
    return p.x > b.l and p.x < b.l + b.w and p.y > b.b and p.y < b.b + b.h
end

local
function normalize_pos(p, b)
    return (p - vec2(b.l, b.b)) * 2 / vec2(b.w, b.h) - 1
end

local
function create_select(label, nodes, x_os, y, spacing, on_change, init_sel, shortcuts)
    local curr_sel = init_sel or 1
    local n = #nodes
    local x_start = x_os + label_w
    local x_end = x_start + n * spacing
    local y_top = y + spacing / 2
    local y_bottom = y - spacing / 2
    local group = am.group()
    group:append(am.translate(x_os, y) ^ am.text(label, "left"))
    local x = x_start + spacing/2
    for i = 1, n do
        group:append(am.translate(x, y) ^ nodes[i])
        x = x + spacing
    end
    group:append(
        am.translate((curr_sel - 1) * spacing + x_start + spacing/2, y):tag"select"
        ^ am.sprite(sprites.select))
    group:action(function()
        if win:mouse_pressed("left") then
            local pos = mouse.pixel_position
            if pos.x > x_start and pos.x < x_end and pos.y > y_bottom and pos.y < y_top then
                curr_sel = math.ceil((pos.x - x_start) / (x_end - x_start) * n)
                group"select""translate".position2d = vec2(x_start + (curr_sel - 1) * spacing + spacing/2, y)
                on_change(curr_sel)
            end
        end
        if shortcuts then
            for sel, key in ipairs(shortcuts) do
                if win:key_pressed(key) then
                    curr_sel = sel
                    group"select""translate".position2d = vec2(x_start + (curr_sel - 1) * spacing + spacing/2, y)
                    on_change(curr_sel)
                    break
                end
            end
        end
    end)
    return group
end

local
function create_checkbox(label, x_os, y, on_change, init_state)
    local sz = 32
    local curr_state = init_state or false
    local x_start = x_os + label_w
    local x_end = x_start + sz
    local y_top = y + sz / 2
    local y_bottom = y - sz / 2
    local group = am.group()
    group:append(am.translate(x_os, y) ^ am.text(label, "left"))
    local x = x_start + sz/2
    local sprite = am.sprite(curr_state and sprites.checkbox_on or sprites.checkbox_off)
    group:append(am.translate(x, y) ^ sprite)
    group:action(function()
        if win:mouse_pressed("left") then
            local pos = mouse.pixel_position
            if pos.x > x_start and pos.x < x_end and pos.y > y_bottom and pos.y < y_top then
                curr_state = not curr_state
                sprite.source = curr_state and sprites.checkbox_on or sprites.checkbox_off
                on_change(curr_state)
            end
        end
    end)
    return group
end

local
function create_button(label, x_os, y, on_press)
    local h = 30
    local x_start = x_os
    local x_end = x_start + label_w
    local y_top = y + h / 2
    local y_bottom = y - h / 2
    local group = am.group{
        am.rect(x_start, y_bottom, x_end, y_top, vec4(0, 1, 1, 1)),
        am.translate(x_os + (x_end - x_start)/2, y+3) ^ am.text(label, vec4(0, 0, 0, 1), "center", "center")
    }
    group:action(function()
        if win:mouse_pressed("left") then
            local pos = mouse.pixel_position
            if pos.x > x_start and pos.x < x_end and pos.y > y_bottom and pos.y < y_top then
                on_press()
            end
        end
    end)
    return group
end

local
function create_slider(label, x_os, y, bg, on_change, init_val, show_val, shortcut)
    local w = bg.width
    local h = bg.height
    local curr_val = init_val or 0
    local lw = label and label_w or 0
    local vw = show_val and val_w or 0
    local x_start = x_os + lw + vw
    local x_end = x_start + w
    local y_top = y + h / 2
    local y_bottom = y - h / 2
    local group = am.group()
    if label then
        group:append(am.translate(x_os, y) ^ am.text(label, "left"))
    end
    local val_txt
    if show_val then
        val_txt = am.text(math.floor(init_val * 255), "left")
        group:append(am.translate(x_os + lw, y) ^ val_txt)
    end
    local x = x_start + w/2
    group:append(am.translate(x, y) ^ am.sprite(bg))
    local slider = am.translate(x, y) ^ am.sprite(sprites.slider)
    group:append(slider)
    local
    function set_slider(val)
        slider.position2d = vec2(x_start + val * w, y)
    end
    set_slider(curr_val)
    local sliding
    local kb_start_val, mouse_start_pos
    group:action(function()
        local pos = mouse.pixel_position
        if win:mouse_pressed"left" then
            if pos.x >= x_start and pos.x <= x_end and pos.y >= y_bottom and pos.y <= y_top then
                sliding = true
                curr_val = (pos.x - x_start) / w
                set_slider(curr_val)
                on_change(curr_val)
                if val_txt then
                    val_txt.text = math.floor(curr_val * 255)
                end
            end
        elseif sliding then
            curr_val = (math.clamp(pos.x, x_start, x_end) - x_start) / w
            set_slider(curr_val)
            on_change(curr_val)
            if val_txt then
                val_txt.text = math.floor(curr_val * 255)
            end
            if win:mouse_released"left" then
                sliding = false
            end
        elseif shortcut and win:key_down(shortcut) then
            if win:key_pressed(shortcut) then
                kb_start_val = curr_val
                mouse_start_pos = pos
                mouse.set_visible(false)
                mouse.clamp = false
            end
            curr_val = math.clamp(kb_start_val + (pos.x - mouse_start_pos.x)/255, 0, 1)
            set_slider(curr_val)
            on_change(curr_val)
            if val_txt then
                val_txt.text = math.floor(curr_val * 255)
            end
        elseif shortcut and mouse_start_pos and win:key_released(shortcut) then
            mouse.set_position(mouse_start_pos)
            mouse.set_visible(true)
            mouse.clamp = true
        end
    end)
    return group
end

local
function create_color_picker(label, x_os, y, on_change, init_val)
    local group = am.group()
    group:append(am.translate(x_os, y) ^ am.text(label, "left"))
    local h = sprites.red_slider.height
    local color = init_val or vec3(1)
    local block = am.rect(x_os + label_w, y-h*1.5, x_os + label_w + h*3, y + h*1.5, vec4(color, 1))
    local r_slider = create_slider(nil, x_os + label_w + h*3 + 5, y-h, sprites.red_slider, function(val)
        color = color{r = val}
        block.color = vec4(color, 1)
        on_change(color)
    end, color.r)
    local g_slider = create_slider(nil, x_os + label_w + h*3 + 5, y, sprites.green_slider, function(val)
        color = color{g = val}
        block.color = vec4(color, 1)
        on_change(color)
    end, color.g)
    local b_slider = create_slider(nil, x_os + label_w + h*3 + 5, y+h, sprites.blue_slider, function(val)
        color = color{b = val}
        block.color = vec4(color, 1)
        on_change(color)
    end, color.b)
    group:append(block)
    group:append(r_slider)
    group:append(g_slider)
    group:append(b_slider)
    return group
end

local ys = {214}
for i = 1, 6 do
    ys[#ys+1] = ys[1] - i * 32
end
local xs = {0, 580, 920}

local
function update_height_src(editor_state)
    local height_src
    if editor_state.curr_brush == webcam_brush and editor_state.is_alpha_view then
        height_src = vec4(0.33, 0.33, 0.33, 0)
    else
        height_src = vec4(0, 0, 0, 1)
    end
    editor_state.draw_brush"bind".height_src = height_src
    editor_state.editor_node"bind".height_src = height_src
end

local
function create_controls(editor_state, terrain_state)
    local view_nodes = {
        am.sprite(sprites.macro_height),
        am.sprite(sprites.macro_color),
        am.sprite(sprites.detail_height),
        am.sprite(sprites.detail_color),
        am.scale(1, -1) ^ am.sprite(sprites.macro_height),
        am.scale(1, -1) ^ am.sprite(sprites.macro_color),
        am.scale(1, -1) ^ am.sprite(sprites.detail_height),
        am.scale(1, -1) ^ am.sprite(sprites.detail_color),
        am.sprite(sprites.hands),
    }
    local view_select = create_select("VIEW:", view_nodes, xs[1], ys[1], 35, function(val)
        terrain_state.settings[editor_state.curr_texture] = editor_state.views[editor_state.curr_view].tex
        if val <= 2 then
            editor_state.curr_view = "floor"
            editor_state.curr_texture = "floor_texture"
        elseif val <= 4 then
            editor_state.curr_view = "floor_detail"
            editor_state.curr_texture = "floor_detail_texture"
        elseif val <= 6 then
            editor_state.curr_view = "ceiling"
            editor_state.curr_texture = "ceiling_texture"
        elseif val <= 8 then
            editor_state.curr_view = "ceiling_detail"
            editor_state.curr_texture = "ceiling_detail_texture"
        else
            editor_state.curr_view = "hands"
            editor_state.curr_texture = "hands_texture"
        end
        terrain_state.settings[editor_state.curr_texture] = editor_state.tmp_texture
        terrain_state:update_settings(terrain_state.settings)
        editor_state.tmp_scene"bind".tex = editor_state.views[editor_state.curr_view].tex
        local mask = editor_state.draw_brush"color_mask"
        if val == 9 then
            -- hands
            editor_state.editor_node"use_program".program = hands_shader
            mask.red = true
            mask.green = true
            mask.blue = true
            mask.alpha = true
            capture_shader = am.shaders.texture2d
            editor_state.is_color_view = true
            editor_state.is_alpha_view = true
        elseif val % 2 == 1 then
            editor_state.editor_node"use_program".program = heightmap_shader
            mask.red = false
            mask.green = false
            mask.blue = false
            mask.alpha = true
            capture_shader = alpha_only_shader
            editor_state.is_color_view = false
            editor_state.is_alpha_view = true
        else
            editor_state.editor_node"use_program".program = color_shader
            mask.red = true
            mask.green = true
            mask.blue = true
            mask.alpha = false
            capture_shader = color_only_shader
            editor_state.is_color_view = true
            editor_state.is_alpha_view = false
        end
        update_height_src(editor_state)
    end, 1, {"1", "2", "3", "4", "5", "6", "7", "8"})
    local brush_nodes = {}
    for i = 1, num_brushes do
        table.insert(brush_nodes, am.scale(28/256) ^ am.sprite(brush_sprite_specs[i]))
    end
    local brush_select = create_select("BRUSH:", brush_nodes, xs[1], ys[2], 30, function(b)
        editor_state.curr_brush = b
        editor_state.draw_brush"brush_sprite".source = brush_sprite_specs[editor_state.curr_brush]
        update_height_src(editor_state)
    end, editor_state.curr_brush)
    local exp1_slider = create_slider("CURVE:", xs[1], ys[3], sprites.exp_slider, function(val)
        editor_state.draw_brush"bind".exp1 = 10 ^ (val * 2 - 1)
    end, 0.5, false, "n")
    local exp2_slider = create_slider(nil, xs[1] + 220, ys[3], sprites.exp_slider, function(val)
        editor_state.draw_brush"bind".exp2 = 10 ^ (val * 2 - 1)
    end, 0.5, false, "m")
    local color_picker = create_color_picker("RGB:", xs[1], ys[4], function(val)
        editor_state.draw_brush"brush_sprite".color = editor_state.draw_brush"brush_sprite".color{rgb = val}
    end, editor_state.draw_brush"brush_sprite".color.rgb)
    local alpha_slider = create_slider("ALPHA:", xs[1], ys[5], sprites.height_slider, function(val)
        editor_state.draw_brush"brush_sprite".color = editor_state.draw_brush"brush_sprite".color{a = val}
    end, editor_state.draw_brush"brush_sprite".color.a, true, "h")
    local blend_modes = {"add", "subtract", "premult", "off", "multiply"}
    local blend_nodes = {
        am.sprite(sprites.blend_add),
        am.sprite(sprites.blend_sub),
        am.sprite(sprites.blend_alpha),
        am.sprite(sprites.blend_eq),
        am.sprite(sprites.blend_mul),
    }
    local blend_select = create_select("BLEND:", blend_nodes, xs[1], ys[6], 30, function(val)
        editor_state.draw_brush"brush_sprite""blend".mode = blend_modes[val]
    end, 3)
    local flow_slider = create_slider("FLOW:", xs[1], ys[7], sprites.flow_slider, function(val)
        if val < 0.1 then
            editor_state.flow = 0
        else
            editor_state.flow = (val - 0.1) / 0.9 * 60
        end
    end, 0)
    local filter_nodes = {
        am.sprite(sprites.filter_linear),
        am.sprite(sprites.filter_nearest),
    }
    local filter_select = create_select("FLTR:", filter_nodes, xs[1] + 220, ys[7], 30, function(val)
        local filter = "nearest"
        if val == 1 then
            filter = "linear"
        end
        editor_state.tmp_texture.minfilter = filter
        editor_state.tmp_texture.magfilter = filter
        terrain_state.settings.filter = filter
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, 1)

    local fog_color_picker = create_color_picker("FOG:", xs[2], ys[1], function(val)
        terrain_state.settings.fog_color = val
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, terrain_state.settings.fog_color.rgb)
    local fog_dist_slider = create_slider("FOG Z:", xs[2], ys[2], sprites.height_slider, function(val)
        terrain_state.settings.fog_dist = val * 2000
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, terrain_state.settings.fog_dist / 2000)
    local ambient_picker = create_color_picker("AMB:", xs[2], ys[3], function(val)
        terrain_state.settings.ambient = val
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, terrain_state.settings.ambient)
    local diffuse_picker = create_color_picker("DIFF:", xs[2], ys[4], function(val)
        terrain_state.settings.diffuse = val
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, terrain_state.settings.diffuse)
    local specular_picker = create_color_picker("SPEC:", xs[2], ys[5], function(val)
        terrain_state.settings.specular = val
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, terrain_state.settings.specular)
    local shininess_slider = create_slider("SHINE:", xs[2], ys[6], sprites.height_slider, function(val)
        terrain_state.settings.shininess = (val ^ 3) * 200
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, 0)
    local speed_slider = create_slider("SPEED:", xs[2], ys[7], sprites.flow_slider, function(val)
        terrain_state.settings.walk_speed = val * 100 + 10
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, 0.5)

    local wireframe_checkbox = create_checkbox("WIRE/F:", xs[3], ys[1], function(val)
        terrain_state.settings.wireframe = val
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, terrain_state.settings.wireframe)
    local noclip_checkbox = create_checkbox("NOCLIP:", xs[3] + 110, ys[1], function(val)
        terrain_state.settings.noclip = val
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, terrain_state.settings.noclip)

    local mesh_nodes = {
        am.sprite(sprites.mesh_low),
        am.sprite(sprites.mesh_med),
        am.sprite(sprites.mesh_high),
    }
    local mesh_select = create_select("MESH:", mesh_nodes, xs[3], ys[2], 30, function(val)
        if val == 1 then
            terrain_state.settings.width = 100
            terrain_state.settings.depth = 100
        elseif val == 2 then
            terrain_state.settings.width = 400
            terrain_state.settings.depth = 300
        elseif val == 3 then
            terrain_state.settings.width = 800
            terrain_state.settings.depth = 600
        end
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, 3)

    local detail_height_slider = create_slider("DTL Y:", xs[3], ys[3], sprites.med_slider, function(val)
        terrain_state.settings.detail_height = val * 0.2 + 0.005
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, 0)
    local detail_scale_slider = create_slider("DTL XZ:", xs[3], ys[4], sprites.med_slider, function(val)
        local s = (val ^ 2) * 0.1 + 0.0005
        terrain_state.settings.floor_detail_scale = s
        terrain_state.settings.ceiling_detail_scale = s
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, 0)
    local ceiling_y_slider = create_slider("SKY Y:", xs[3], ys[5], sprites.med_slider, function(val)
        terrain_state.settings.ceiling_y_offset = (val ^ 2 * 1000) - 100
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, 0)
    local y_scale_slider = create_slider("VSCALE:", xs[3], ys[6], sprites.med_slider, function(val)
        local s = (val ^ 2) * 500 + 50
        terrain_state.settings.floor_y_scale = s
        terrain_state.settings.ceiling_y_scale = s
        terrain_state:update_settings(terrain_state.settings)
        editor_state.modified = true
    end, 0)

    local reset_button = create_button("RESET", xs[2] + 560, ys[7], function()
        if am.platform ~= "html" or not editor_state.modified
            or am.eval_js("confirm('You have unsaved changes, are you sure you want to reset? (all unsaved changes will be lost)');")
        then
            reset()
        end
    end)

    local upload_button = create_button("UPLOAD", xs[1] + 490, ys[1], function()
        win.lock_pointer = false
        local img = upload.start_image_upload()
        win.scene:action(function()
            local base64 = upload.image_upload_successful()
            if base64 then
                win.lock_pointer = true
                local img
                local ok = pcall(function() 
                    img = am.decode_png(am.base64_decode(base64))
                end)
                if not ok or img.width ~= 512 or img.height ~= 512 then
                    am.eval_js("alert('image must be a 512x512 png');");
                    return true
                end
                local view = editor_state.views[editor_state.curr_view]
                view.fb:read_back()
                if editor_state.is_color_view then
                    local dr = view.img.buffer:view("ubyte", 0, 4)
                    local sr = img.buffer:view("ubyte", 0, 4)
                    local dg = view.img.buffer:view("ubyte", 1, 4)
                    local sg = img.buffer:view("ubyte", 1, 4)
                    local db = view.img.buffer:view("ubyte", 2, 4)
                    local sb = img.buffer:view("ubyte", 2, 4)
                    dr:set(sr)
                    dg:set(sg)
                    db:set(sb)
                    if editor_state.is_alpha_view then
                        local da = view.img.buffer:view("ubyte", 3, 4)
                        local sa = img.buffer:view("ubyte", 3, 4)
                        da:set(sa)
                    end
                elseif editor_state.is_alpha_view then
                    local dst = view.img.buffer:view("ubyte", 3, 4)
                    local src = img.buffer:view("ubyte", 0, 4)
                    dst:set(src)
                end
                return true
            end
        end)
    end)

    local download_button = create_button("DOWNLD", xs[1] + 490, ys[2], function()
        local view = editor_state.views[editor_state.curr_view]
        view.fb:read_back()
        local dst = am.image_buffer(512)
        local src = view.img
        if editor_state.is_color_view then
            local dr = dst.buffer:view("ubyte", 0, 4)
            local sr = src.buffer:view("ubyte", 0, 4)
            local dg = dst.buffer:view("ubyte", 1, 4)
            local sg = src.buffer:view("ubyte", 1, 4)
            local db = dst.buffer:view("ubyte", 2, 4)
            local sb = src.buffer:view("ubyte", 2, 4)
            local da = dst.buffer:view("ubyte", 3, 4)
            dr:set(sr)
            dg:set(sg)
            db:set(sb)
            if editor_state.is_alpha_view then
                local sa = src.buffer:view("ubyte", 3, 4)
                da:set(sa)
            else
                da:set(255)
            end
        else
            local dr = dst.buffer:view("ubyte", 0, 4)
            local dg = dst.buffer:view("ubyte", 1, 4)
            local db = dst.buffer:view("ubyte", 2, 4)
            local da = dst.buffer:view("ubyte", 3, 4)
            local sa = src.buffer:view("ubyte", 3, 4)
            dr:set(sa)
            dg:set(sa)
            db:set(sa)
            da:set(255)
        end
        download.download_image(dst)
    end)

    local title_button = create_button("TITLE", xs[2] + 720-480, ys[7], function()
        local title = terrain_state.settings.title or ""
        title = title:gsub("%'", "")
        title = am.eval_js("prompt('Enter a title:', '"..title.."');")
        if title then
            if title == "" then
                title = nil
            end
            terrain_state.settings.title = title
            focus.regain("Title updated")
        else
            focus.regain("Title not updated")
        end
        editor_state.modified = true
    end)
    local share_button = create_button("SHARE", xs[2] + 800-480, ys[7], function()
        gist.share(
            editor_state.views.floor,
            editor_state.views.ceiling,
            editor_state.views.floor_detail,
            editor_state.views.ceiling_detail,
            editor_state.views.hands,
            terrain_state
        )
    end)
    local save_button = create_button("SAVE", xs[2] + 880-480, ys[7], function()
        save.save(
            editor_state.views.floor,
            editor_state.views.ceiling,
            editor_state.views.floor_detail,
            editor_state.views.ceiling_detail,
            editor_state.views.hands,
            terrain_state
        )
        editor_state.modified = false
    end)
    local help_button = create_button("HELP", xs[2] + 960-480, ys[7], function()
        help.show()
    end)

    local group = am.group()
    group:append(
        am.bind{P = mat4(1), MV = mat4(1)}
        ^ am.rect(-1, -1, 1, 1, vec4(0.2, 0.2, 0.2, 1)))
    group:append(view_select)
    group:append(brush_select)
    group:append(exp1_slider)
    group:append(exp2_slider)
    group:append(color_picker)
    group:append(alpha_slider)
    group:append(blend_select)
    group:append(flow_slider)
    group:append(filter_select)

    group:append(fog_color_picker)
    group:append(fog_dist_slider)
    group:append(ambient_picker)
    group:append(diffuse_picker)
    group:append(specular_picker)
    group:append(shininess_slider)
    group:append(speed_slider)

    group:append(wireframe_checkbox)
    group:append(noclip_checkbox)
    group:append(mesh_select)

    group:append(detail_height_slider)
    group:append(detail_scale_slider)
    group:append(ceiling_y_slider)
    group:append(y_scale_slider)

    group:append(reset_button)
    if am.platform == "html" then
        group:append(upload_button)
        group:append(download_button)
        group:append(title_button)
        group:append(share_button)
        group:append(save_button)
    end
    group:append(help_button)

    local node = 
        am.viewport(0, 0, 0, 0)
        ^ am.bind{
            P = math.ortho(0, win.pixel_width, 0, 230),
            MV = mat4(1),
        }
        ^ group
    function node:update_layout(layout)
        local w, h = win.pixel_width, layout.bottom
        node"bind".P = math.ortho(0, w, 0, h)
        node"viewport".width = w
        node"viewport".height = h
    end
    return node
end

function editor.create(floor, ceiling, floor_detail, ceiling_detail, hands, terrain_state)
    local editor_state = {
        flow = 0,
        views = {
            floor = floor,
            ceiling = ceiling,
            floor_detail = floor_detail,
            ceiling_detail = ceiling_detail,
            hands = hands,
        },
        curr_view = "floor",
        is_color_view = false,
        is_alpha_view = true,
        curr_texture = "floor_texture",
        curr_brush = 4,
        zoom = 1,
        edit_mode = false,
        brush_fb = am.framebuffer(sprites.texture),
        modified = false,
    }
    local brush_size = vec2(0.0005)
    local brush_angle = 0
    local arrow_scale = 0.01
    local editor_bounds = {
        l = 0,
        b = 0,
        w = 0,
        h = 0,
    }
    local draw_brush =
        am.color_mask(false, false, false, true)
        ^ am.bind{
            P = mat4(1),
            MV = mat4(1),
            exp1 = 1,
            exp2 = 1,
            height_src = vec4(0, 0, 0, 1)
        }
        ^ am.translate(0, 0)
        ^ am.rotate(brush_angle):tag"brush_rotate"
        ^ am.scale(brush_size):tag"brush_size"
        ^ {
            am.sprite(brush_sprite_specs[editor_state.curr_brush]):tag"brush_sprite"
        }
    draw_brush"brush_sprite""blend".mode = "premult"
    draw_brush"brush_sprite""use_program".program = draw_shader
    editor_state.draw_brush = draw_brush
    local tmp_texture = am.texture2d(floor.tex.width, floor.tex.height)
    tmp_texture.wrap = "mirrored_repeat"
    tmp_texture.filter = "linear"
    editor_state.tmp_texture = tmp_texture
    local tmp_fb = am.framebuffer(tmp_texture)
    local tmp_scene = 
        am.use_program(am.shaders.texture)
        ^ am.bind{
            P = mat4(1),
            MV = mat4(1),
            tex = editor_state.views[editor_state.curr_view].tex,
        }
        ^ {
            am.bind{
                vert = am.rect_verts_3d(-1, -1, 1, 1),
                uv = am.rect_verts_2d(0, 0, 1, 1),
            }
            ^ am.draw("triangles", am.rect_indices())
            ,
            draw_brush
        }
    editor_state.tmp_scene = tmp_scene
    local arrow =
        am.translate(0, 0)
        ^ am.rotate(0)
        ^ am.scale(arrow_scale)
        ^ am.sprite(sprites.arrow)
    local w = sprites.brush1.width/2
    local cursor = 
        am.translate(0, 0)
        ^ am.rotate(brush_angle)
        ^ am.scale(brush_size)
        ^ am.use_program(am.shaders.color2d)
        ^ am.bind{
            color = vec4(0, 1, 1, 1),
            vert = am.vec2_array{-w, w, -w, -w, w, -w, w, w, -w, w},
        }
        ^ am.draw"line_strip"
    local editor_node = 
        am.viewport(0, 0, 0, 0)
        ^ am.use_program(heightmap_shader)
        ^ am.bind{
            P = mat4(1),
            MV = mat4(1),
            tex = tmp_texture,
            height_src = vec4(0, 0, 0, 1),
        }
        ^ am.scale(1):tag"bg"
        ^ am.translate(0, 0)
        ^ {
            am.bind{
                vert = am.rect_verts_2d(-1, -1, 1, 1),
                uv = am.rect_verts_2d(0, 0, 1, 1),
            }
            ^ am.draw("triangles", am.rect_indices())
            ,
            arrow
            ,
            cursor
        }
    editor_state.editor_node = editor_node
    local controls = create_controls(editor_state, terrain_state)
    local node = 
        am.depth_test("always", false)
        ^ {editor_node, controls}

    local flow_accum = 0
    local prev_norm_pos = nil
    local norm_pos = nil
    local start_angle
    local rot_pos0 = nil
    local x_pos0 = nil
    local y_pos0 = nil
    local z_pos0 = nil
    local rot_mouse_start_pos = nil
    local x_mouse_start_pos = nil
    local y_mouse_start_pos = nil
    local z_mouse_start_pos = nil
    local start_size = nil
    local start_alpha = nil

    node:action(function()
        webcam_tex:capture_video()
        tmp_fb:render(tmp_scene)
        local pos = mouse.pixel_position
        prev_norm_pos = norm_pos
        norm_pos = normalize_pos(pos, editor_bounds)
        if win:key_down"r" then
            if win:key_pressed"r" then
                rot_pos0 = norm_pos
                rot_mouse_start_pos = mouse.pixel_position
                mouse.set_visible(false)
                start_angle = brush_angle
                mouse.clamp = false
            end
            local angle_change = norm_pos.x - rot_pos0.x
            brush_angle = start_angle - angle_change
            draw_brush"brush_rotate".angle = brush_angle
        elseif win:key_released"r" then
            if rot_pos0 then
                mouse.set_position(rot_mouse_start_pos)
                rot_pos0 = nil
                mouse.set_visible(true)
                mouse.clamp = true
            end
        end
        if win:key_down"x" then
            if win:key_pressed"x" then
                x_pos0 = norm_pos
                x_mouse_start_pos = mouse.pixel_position
                mouse.set_visible(false)
                start_size = brush_size
                mouse.clamp = false
            end
            brush_size = brush_size{x = start_size.x + 0.005 * (norm_pos.x - x_pos0.x)}
            draw_brush"brush_size".scale2d = brush_size
        elseif win:key_released"x" then
            if x_pos0 then
                mouse.set_position(x_mouse_start_pos)
                x_pos0 = nil
                mouse.set_visible(true)
                mouse.clamp = true
            end
        end
        if win:key_down"y" then
            if win:key_pressed"y" then
                y_pos0 = norm_pos
                y_mouse_start_pos = mouse.pixel_position
                mouse.set_visible(false)
                start_size = brush_size
                mouse.clamp = false
            end
            brush_size = brush_size{y = start_size.y + 0.005 * (norm_pos.x - y_pos0.x)}
            draw_brush"brush_size".scale2d = brush_size
        elseif win:key_released"y" then
            if y_pos0 then
                mouse.set_position(y_mouse_start_pos)
                y_pos0 = nil
                mouse.set_visible(true)
                mouse.clamp = true
            end
        end
        if win:key_down"z" then
            if win:key_pressed"z" then
                z_pos0 = norm_pos
                z_mouse_start_pos = mouse.pixel_position
                mouse.set_visible(false)
                start_size = brush_size
                mouse.clamp = false
            end
            brush_size = start_size + vec2(0.005 * (norm_pos.x - z_pos0.x), 0.005 * (norm_pos.x - z_pos0.x) * (start_size.y / start_size.x))
            draw_brush"brush_size".scale2d = brush_size
        elseif win:key_released"z" then
            if z_pos0 then
                mouse.set_position(z_mouse_start_pos)
                z_pos0 = nil
                mouse.set_visible(true)
                mouse.clamp = true
            end
        end
        if win:key_pressed"t" then
            brush_size = vec2(math.max(
                math.abs(draw_brush"brush_size".scale2d.x), math.abs(draw_brush"brush_size".scale2d.y)
            ))
            draw_brush"brush_size".scale2d = brush_size
            brush_angle = 0
            draw_brush"brush_rotate".angle = brush_angle
        end
        if win:key_pressed"c" and not mouse.cursor.hidden and in_bounds(pos, editor_bounds) then
            local sprite = brush_sprite_specs[editor_state.curr_brush]
            local x1 = sprite.s1 * 2 - 1
            local y1 = sprite.t1 * 2 - 1
            local x2 = sprite.s2 * 2 - 1
            local y2 = sprite.t2 * 2 - 1
            local s1 = brush_size * sprite.width * 0.5
            local os = -editor_node"translate".position2d + norm_pos / editor_node"bg""scale".scale.x
            local q = quat(brush_angle)
            local p1 = q * (vec2(-1, 1) * s1) + os
            local p2 = q * (vec2(-1, -1) * s1) + os
            local p3 = q * (vec2(1, -1) * s1) + os
            local p4 = q * (vec2(1, 1) * s1) + os
            p1 = p1 * 0.5 + 0.5
            p2 = p2 * 0.5 + 0.5
            p3 = p3 * 0.5 + 0.5
            p4 = p4 * 0.5 + 0.5
            local node = 
                am.use_program(capture_shader)
                ^ am.bind{
                    MV = mat4(1),
                    P = mat4(1),
                    tex = editor_state.views[editor_state.curr_view].tex,
                    vert = am.rect_verts_2d(x1, y1, x2, y2),
                    uv = am.vec2_array{p1, p2, p3, p4}
                }
                ^ am.draw("triangles", am.rect_indices())
            editor_state.brush_fb:render(node)
        end
        if prev_norm_pos and (win:key_down("lshift") or win:key_down("rshift")) then
            local t = editor_node"translate"
            t.position2d = t.position2d + (norm_pos - prev_norm_pos) / editor_node"bg""scale".scale.x
        else
            if not mouse.cursor.hidden then
                draw_brush"translate".position2d = norm_pos / editor_node"scale".scale.x - editor_node"translate".position2d
            end
            if mouse.cursor.hidden or in_bounds(pos, editor_bounds) then
                if editor_state.flow > 0 then
                    if win:mouse_down"left" then
                        flow_accum = flow_accum + am.delta_time
                        while flow_accum > 1 / editor_state.flow do
                            editor_state.views[editor_state.curr_view].fb:render(draw_brush)
                            flow_accum = flow_accum - 1 / editor_state.flow
                        end
                        editor_state.modified = true
                    end
                else
                    if win:mouse_pressed"left" then
                        editor_state.views[editor_state.curr_view].fb:render(draw_brush)
                        editor_state.modified = true
                    end
                end
            end
        end
        if win:key_pressed("0") then
            editor_node:action(am.tween(editor_state, 0.1, {zoom = editor_state.zoom + 20}, am.ease.cubic))
        elseif win:key_pressed("9") then
            editor_node:action(am.tween(editor_state, 0.1, {zoom = editor_state.zoom - 20}, am.ease.cubic))
        elseif win:mouse_wheel_delta().y ~= 0 then
            editor_state.zoom = editor_state.zoom + win:mouse_wheel_delta().y * 2
        end
        editor_node"bg""scale".scale2d = vec2(2 ^ (editor_state.zoom / 20))
        arrow_scale = 3 / editor_bounds.w
        arrow"scale".scale2d = arrow_scale / editor_node"bg""scale".scale2d
        cursor"scale".scale2d = brush_size
        cursor"rotate".angle = brush_angle
        cursor"translate".position2d = draw_brush"translate".position2d
    end)
    function node:update_layout(layout)
        editor_bounds.b, editor_bounds.w, editor_bounds.h = layout.bottom, layout.left, win.pixel_height - layout.bottom
        editor_node"viewport".left = editor_bounds.l
        editor_node"viewport".bottom = editor_bounds.b
        editor_node"viewport".width = editor_bounds.w
        editor_node"viewport".height = editor_bounds.h
        controls:update_layout(layout)
    end
    function node:update_arrow(pos, facing)
        arrow"translate".position2d = pos * 2 - 1
        arrow"rotate".angle = facing
    end
    function node:set_mode(edit_mode)
        if edit_mode then
            terrain_state.settings[editor_state.curr_texture] = tmp_texture
        else
            terrain_state.settings[editor_state.curr_texture] = editor_state.views[editor_state.curr_view].tex
        end
        terrain_state:update_settings(terrain_state.settings)
        editor_state.edit_mode = edit_mode
    end
    node.editor_state = editor_state
    return node
end
