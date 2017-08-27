local win = require "window"

local mouse = {}

mouse.cursor = 
    am.bind{P = math.ortho(0, win.pixel_width, 0, win.pixel_height, -1, 1)}
    ^ am.translate(0, 0)
    ^ am.blend"invert"
    ^ { am.rect(-1, -10000, 1, 10000), am.rect(-10000, -1, 10000, 1) }
mouse.pixel_position = vec2(0)
mouse.clamp = true

mouse.cursor:action(function(node)
    if win.lock_pointer then
        mouse.pixel_position = mouse.pixel_position + win:mouse_pixel_delta()
        if mouse.clamp then
            mouse.pixel_position = math.clamp(
                mouse.pixel_position,
                vec2(0), vec2(win.pixel_width, win.pixel_height))
        end
    else
        mouse.pixel_position = win:mouse_pixel_position()
    end
    node"bind".P = math.ortho(0, win.pixel_width, 0, win.pixel_height, -1, 1)
    node"translate".position2d = mouse.pixel_position
end)

function mouse.set_visible(visible)
    mouse.cursor.hidden = not visible
    win.lock_pointer = not visible
end

function mouse.set_position(pos)
    mouse.pixel_position = pos
    mouse.cursor"translate".position2d = mouse.pixel_position
end

mouse.cursor.hidden = true

return mouse
