local
function convert(prefix)
    local color_filename = prefix.."_color.png"
    local heightmap_filename = prefix.."_heightmap.png"
    local color_image = am.load_image(color_filename)
    local heightmap_image = am.load_image(heightmap_filename)
    if color_image.width ~= heightmap_image.width then
        error(string.format("%s and %s have different widths (%d vs %d)",
            color_filename, heightmap_filename, color_image.width, heightmap_image.width))
    end
    if color_image.height ~= heightmap_image.height then
        error(string.format("%s and %s have different heights (%d vs %d)",
            color_filename, heightmap_filename, color_image.height, heightmap_image.height))
    end
    local alpha_view = color_image.buffer:view("ubyte", 3, 4)
    local depth_view = heightmap_image.buffer:view("ubyte", 0, 4)
    alpha_view:set(depth_view)
    local texture = am.texture2d{
        image = color_image,
        swrap = "mirrored_repeat",
        twrap = "mirrored_repeat",
        format = "rgba",
        minfilter = "linear",
        magfilter = "linear",
    }
    am.save_image(color_image, prefix..".png")
end

local n = arg[1]
if not n then
    error("missing arg")
end

convert("floor"..n)
convert("floor"..n.."_detail")
convert("ceiling"..n)
convert("ceiling"..n.."_detail")
