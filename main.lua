local win = require "window"
local texture = require "texture"
local terrain = require "terrain"
local editor = require "editor"
local mouse = require "mouse"
local gist = require "gist"
local save = require "save"
local help = require "help"
local title = require "title"

local
function start(floor, floor_detail, ceiling, ceiling_detail, settings)
    if not settings.links then
        settings.links = {}
    end
    local terrain_state = terrain.create(settings)

    local scene = terrain_state.node
    local ed = editor.create(floor, ceiling, floor_detail, ceiling_detail, terrain_state)
    ed.hidden = true
    ed.paused = true

    local messages = am.group()

    local top = am.group{
        scene,
        ed,
        mouse.cursor,
        messages,
    }

    local bot = 230

    local edit_mode = false
    local prev_edit_mode = not edit_mode
    terrain_state.paused = edit_mode
    local layout = {
        left = 200,
        bottom = bot,
    }

    local
    function update_layout(t)
        local t = t or 0.2
        if edit_mode ~= prev_edit_mode or win:resized() then
            if edit_mode then
                local l = math.min(win.pixel_width * 0.5, win.pixel_height - bot)
                top:action("layout", am.series{
                    function()
                        ed.hidden = false
                        ed.paused = false
                        return true
                    end,
                    am.tween(layout, t, {
                        left = l,
                        bottom = win.pixel_height - l,
                    }, am.ease.cubic),
                })
                messages.hidden = true
            else
                top:action("layout", am.series{
                    am.tween(layout, t, {
                        left = 0,
                        bottom = 0,
                    }, am.ease.cubic),
                    function()
                        ed.hidden = true
                        ed.paused = true
                        return true
                    end,
                })
                messages.hidden = false
            end
        end
        prev_edit_mode = edit_mode
        terrain_state:update_layout(layout)
        ed:update_layout(layout)
    end

    update_layout(0)

    local curr_level = ""
    local
    function load_level(level)
        local settings = am.load_script("settings"..level..".lua")()
        floor = texture.read_texture("floor"..level..".png", settings.filter)
        floor_detail = texture.read_texture("floor"..level.."_detail.png", settings.filter)
        ceiling = texture.read_texture("ceiling"..level..".png", settings.filter)
        ceiling_detail = texture.read_texture("ceiling"..level.."_detail.png", settings.filter)
        ed:set_textures(floor, ceiling, floor_detail, ceiling_detail)
        settings.floor_texture = floor.tex
        settings.floor_detail_texture = floor_detail.tex
        --settings.floor_side_texture = floor_side.tex
        settings.ceiling_texture = ceiling.tex
        settings.ceiling_detail_texture = ceiling_detail.tex
        --settings.ceiling_side_texture = floor_side.tex
        terrain_state:update_settings(settings)
        collectgarbage()
        collectgarbage()
        curr_level = level
    end

    top:action(function()
        mouse.cursor:update()
        if win:key_pressed("escape") then
            win:close()
            return true
        --elseif win:key_pressed("lalt") or win:key_pressed("ralt") then
        --    win.lock_pointer = false
        --elseif win:mouse_pressed("left") then
        --    win.lock_pointer = true
        elseif win:key_pressed("p") then
            terrain_state.paused = not terrain_state.paused
        elseif win:key_pressed("j") then
            terrain_state:reset_pos()
        --elseif win:key_pressed"f1" then
        --    help.show()
        --    return
        elseif win:key_pressed("e") then
            edit_mode = not edit_mode
            mouse.set_visible(edit_mode)
            terrain_state.paused = edit_mode
            ed:set_mode(edit_mode)
        elseif (win:key_down"lctrl" or win:key_down"rctrl") and win:key_pressed("s") then
            floor.fb:read_back()
            ceiling.fb:read_back()
            floor_detail.fb:read_back()
            ceiling_detail.fb:read_back()
            am.save_image_as_png(floor.img, "floor"..curr_level..".png")
            am.save_image_as_png(floor_detail.img, "floor"..curr_level.."_detail.png")
            am.save_image_as_png(ceiling.img, "ceiling"..curr_level..".png")
            am.save_image_as_png(ceiling_detail.img, "ceiling"..curr_level.."_detail.png")
        elseif win:key_pressed("f") then
            if win.mode == "fullscreen" then
                win.mode = "windowed"
            else
                win.mode = "fullscreen"
            end
        end
        update_layout()
        ed:update_arrow(terrain_state.pos_abs, terrain_state.facing)
        if not edit_mode then
            if win:key_pressed"l" then
                local caption = am.eval_js("prompt('Enter link caption. (Press enter to...)');")
                if not caption or caption == "" then
                    caption = "follow link"
                end
                local url = am.eval_js("prompt('Enter link URL:');")
                if url and url ~= "" then
                    table.insert(terrain_state.settings.links, {
                        caption = caption,
                        url = url,
                        pos = terrain_state.pos,
                    })
                end
            end
            for i, link in ipairs(settings.links) do
                if math.distance(terrain_state.pos, link.pos) < 0.03 then
                    if not link.node then
                        local txt = am.text("Press enter to "..link.caption, vec4(0, 0, 0, 1), "center", "center")
                        local w, h = txt.width, txt.height
                        local bg = am.rect(-w/2-10, -h/2-10, w/2+10, h/2+10)
                        link.node = am.group{
                            am.translate(win.left + win.width/2, win.bottom + win.height/2) 
                            ^ am.scale(2) ^ am.depth_test"always" ^ { bg, txt }
                        }
                        messages:append(link.node)
                    end
                    if win:key_pressed"enter" then
                        am.eval_js("window.location = '"..link.url.."';")
                        log("followed link to "..link.url)
                    end
                    if win:key_pressed"u" then
                        messages:remove(link.node)
                        link.node = nil
                        table.remove(settings.links, i)
                    end
                    break;
                else
                    if link.node then
                        messages:remove(link.node)
                        link.node = nil
                    end
                end
            end
        end
    end)

    win.scene = top
    title.show(settings.title)
end

local gist_id = gist.get_gist_id()
if gist_id then
    gist.load_gist(gist_id, start)
elseif save.is_save() then
    save.load_save(start)
else
    local settings = am.load_script("settings.lua")()
    local floor = texture.read_texture("floor.png")
    local floor_detail = texture.read_texture("floor_detail.png")
    --local floor_side = texture.read_texture("side.jpg")
    local ceiling = texture.read_texture("ceiling.png")
    local ceiling_detail = texture.read_texture("ceiling_detail.png")
    settings.floor_texture = floor.tex
    settings.ceiling_texture = ceiling.tex
    settings.floor_detail_texture = floor_detail.tex
    settings.ceiling_detail_texture = ceiling_detail.tex
    --settings.floor_side_texture = floor_side.tex
    --settings.ceiling_side_texture = floor_side.tex

    start(floor, floor_detail, ceiling, ceiling_detail, settings)
end
