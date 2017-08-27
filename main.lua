local win = require "window"
local texture = require "texture"
local terrain = require "terrain"
local editor = require "editor"
local mouse = require "mouse"
local gist = require "gist"
local save = require "save"
local help = require "help"
local title = require "title"
local focus = require "focus"

function start_engine(floor, floor_detail, ceiling, ceiling_detail, hands, settings, edit_mode)
    if edit_mode == nil then
        edit_mode = false
    end
    if not settings.links then
        settings.links = {}
    end
    local terrain_state = terrain.create(settings)

    local scene = terrain_state.node
    local ed = editor.create(floor, ceiling, floor_detail, ceiling_detail, hands, terrain_state)
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

    mouse.set_visible(edit_mode)
    ed:set_mode(edit_mode)

    local prev_edit_mode = not edit_mode
    terrain_state.paused = edit_mode
    local layout = {
        left = 200,
        bottom = bot,
    }

    local link_threshold = 0.03

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

    top:action(function()
        mouse.cursor:update()
        if am.platform ~= "html" and win:key_pressed("escape") then
            win:close()
            return true
        elseif am.platform ~= "html" and (win:key_pressed("lalt") or win:key_pressed("ralt")) then
            win.lock_pointer = false
        elseif am.platform ~= "html" and win:mouse_pressed("left") then
            win.lock_pointer = true
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
            hands.fb:read_back()
            am.save_image_as_png(floor.img, "floor.png")
            am.save_image_as_png(floor_detail.img, "floor_detail.png")
            am.save_image_as_png(ceiling.img, "ceiling.png")
            am.save_image_as_png(ceiling_detail.img, "ceiling_detail.png")
            am.save_image_as_png(hands.img, "hands.png")
        elseif win:key_pressed("f") then
            if win.mode == "fullscreen" then
                win.mode = "windowed"
            else
                win.mode = "fullscreen"
            end
        end
        --[[
        if am.platform ~= "html" then
            if win:key_pressed"f1" then
                save.load_save(start_engine, "demo1.json")
            elseif win:key_pressed"f2" then
                save.load_save(start_engine, "demo2.json")
            elseif win:key_pressed"f3" then
                save.load_save(start_engine, "demo3.json")
            elseif win:key_pressed"f4" then
                save.load_save(start_engine, "demo4.json")
            elseif win:key_pressed"f5" then
                save.load_save(start_engine, "demo5.json")
            elseif win:key_pressed"f6" then
                save.load_save(start_engine, "demo6.json")
            elseif win:key_pressed"f7" then
                save.load_save(start_engine, "demo7.json")
            elseif win:key_pressed"f8" then
                save.load_save(start_engine, "demo8.json")
            end
        end
        ]]
        update_layout()
        ed:update_arrow(terrain_state.pos_abs, terrain_state.facing)
        if not edit_mode then
            if win:key_pressed"l" then
                local caption = am.eval_js("prompt('Enter link caption (the displayed message will be: \"Press enter to <your caption>\")');")
                if caption then
                    if caption == "" then
                        caption = "follow link"
                    end
                    local url = am.eval_js("prompt('Enter link URL (including http://):');")
                    if url and url ~= "" then
                        local new_link = {
                            caption = caption,
                            url = url,
                            pos = terrain_state.pos,
                        }
                        local replaced_link = false
                        for i, link in ipairs(settings.links) do
                            if math.distance(terrain_state.pos, link.pos) < link_threshold then
                                messages:remove(link.node)
                                link.node = nil
                                settings.links[i] = new_link
                                replaced_link = true
                                break
                            end
                        end
                        if not replaced_link then
                            table.insert(settings.links, new_link)
                        end
                        ed.editor_state.modified = true
                        focus.regain("Link trigger created")
                    else
                        focus.regain("Link trigger not created")
                    end
                else
                    focus.regain("Link trigger not created")
                end
            end
            for i, link in ipairs(settings.links) do
                if math.distance(terrain_state.pos, link.pos) < link_threshold then
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
                        if not ed.editor_state.modified
                            or am.eval_js("confirm('You have unsaved changes, are you sure you want to leave this page? (all unsaved changes will be lost)');")
                        then
                            am.eval_js("window.location = '"..link.url.."';")
                        end
                    end
                    if win:key_pressed"u" then
                        messages:remove(link.node)
                        link.node = nil
                        table.remove(settings.links, i)
                        ed.editor_state.modified = true
                    end
                    break;
                else
                    if link.node then
                        messages:remove(link.node)
                        link.node = nil
                    end
                end
            end
            if win:key_pressed"i" then
                settings.start_pos = terrain_state.pos
                terrain_state:update_settings(settings)
            end
        end
    end)

    win.scene = top
    title.show(settings.title)
end

function reset()
    local settings = am.load_script("settings.lua")()
    local floor = texture.read_texture("floor.png")
    local floor_detail = texture.read_texture("floor_detail.png")
    --local floor_side = texture.read_texture("side.jpg")
    local ceiling = texture.read_texture("ceiling.png")
    local ceiling_detail = texture.read_texture("ceiling_detail.png")
    local hands = texture.read_hand_texture("hands.png")
    settings.floor_texture = floor.tex
    settings.ceiling_texture = ceiling.tex
    settings.floor_detail_texture = floor_detail.tex
    settings.ceiling_detail_texture = ceiling_detail.tex
    settings.hands_texture = hands.tex
    --settings.floor_side_texture = floor_side.tex
    --settings.ceiling_side_texture = floor_side.tex

    start_engine(floor, floor_detail, ceiling, ceiling_detail, hands, settings)
end

local gist_id = gist.get_gist_id()
if gist_id then
    gist.load_gist(gist_id, start_engine)
elseif save.is_save() then
    save.load_save(start_engine)
else
    reset()
end

noglobals()
