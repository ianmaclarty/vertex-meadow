local title = {}

local win = require "window"

function title.show(title)
    title = title or ""
    local controls = [[
~~~~~~~~~~~~~~~~~~~*~~~~~~~~~~~~~~~~~~~
USE ARROW KEYS OR WASD + MOUSE TO MOVE

PRESS ALT-ENTER FOR FULLSCREEN

PRESS E TO EDIT

CLICK TO BEGIN]]
    local txt = am.group{
        am.translate(win.left + win.width/2, win.bottom + win.height/2 + 50) ^ am.scale(2) ^ am.text(title, "center", "center"),
        am.translate(win.left + win.width/2, win.bottom + win.height/2 - 150) ^ am.scale(1.5) ^ am.text(controls, "center", "center")
    }
    local old_scene = win.scene
    local old_bg = win.clear_color
    win.scene = txt
    win.clear_color = vec4(0, 0, 0, 1)
    win.scene:action(function()
        if win:mouse_pressed"left" then
            win.scene = old_scene
            win.clear_color = old_bg
            return true
        end
    end)
end

return title
