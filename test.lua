local win = require"window"
win.scene = am.group()
win.scene:action(function()
    if win:key_pressed"enter" then
        win.scene = am.translate(win.left + win.width/2, win.height/2) ^ am.scale(2) ^ am.text("SHARING... PLEASE WAIT", "center", "center")
    end
end)

