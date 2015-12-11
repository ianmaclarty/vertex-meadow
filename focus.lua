local focus = {}

local win = require "window"

function focus.regain(msg)
    local node = am.translate(win.left + win.width/2, win.bottom + win.height/2)
        ^ am.scale(2)
        ^ am.text(msg.."\n\n".."Click to continue", "center", "center")
    local old_scene = win.scene
    local old_bg = win.clear_color
    win.scene = node
    win.clear_color = vec4(0, 0, 0, 1)
    win.scene:action(function()
        if win:mouse_pressed"left" then
            win.scene = old_scene
            win.clear_color = old_bg
            return true
        end
    end)
end

return focus
