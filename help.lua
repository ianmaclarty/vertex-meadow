local help = {}

local win = require "window"

local help_text = am.text([[
    ******************* VERTEX MEADOW HELP *****************

PRESS E TO TOGGLE BETWEEN EDIT AND EXPLORE MODES

EDIT MODE:                            EXPLORE MODE:
------------------------------------  -------------------
1-8:             SWITCH VIEW          ARROWS/WASD: MOVE
Z+MOUSE:         BRUSH SIZE           MOUSE: LOOK
X+MOUSE:         BRUSH SIZE X         SPACE: JUMP
Y+MOUSE:         BRUSH SIZE Y         ]]..(am.platform=="html" and "L: CREATE LINK AT CURRENT POS" or "")..[[

R+MOUSE:         ROTATE BRUSH         ]]..(am.platform=="html" and "U: DELETE LINK AT CURRENT POS" or "")..[[

H+MOUSE:         BRUSH ALPHA(HEIGHT)  I: SET INITIAL POS
N+MOUSE:         BRUSH CURVE PARAM1
M+MOUSE:         BRUSH CURVE PARAM2
C:               CAPTURE CUSTOM BRUSH
SHIFT+MOUSE:     PAN
0/9/MOUSE WHEEL: ZOOM
T:               RESET BRUSH SIZE+SCALE
P:               PAUSE/UNPAUSE (USE TO MOVE WHILE IN EDIT MODE)
J:               JUMP TO START POS

IF THE MOUSE CURSOR BECOMES OUT-OF-SYNC,
CLICK ON THE 3D VIEW TO LET IT RECAPTURE YOUR CURSOR

IF YOU MAKE SOMETHING COOL OR FIND A BUG PLEASE LET ME KNOW:
IAN@IANMACLARTY.COM OR @MUCLORTY ON TWITTER.
]], "left", "center")


function help.show()
    local help_node = am.translate(win.left + win.width/2 - 250, win.bottom + win.height/2) ^ help_text
    local old_scene = win.scene
    local old_bg = win.clear_color
    win.scene = help_node
    win.clear_color = vec4(0, 0, 0, 1)
    win.scene:action(function()
        if win:key_pressed"e" or win:key_pressed"escape" or win:key_pressed"enter" or win:key_pressed"space" or win:mouse_pressed"left" then
            win.scene = old_scene
            win.clear_color = old_bg
            return true
        end
    end)
end

return help
