local win = require "window"

local terrain = {}
--
local terrain_vshader = [[
    precision highp float;
    attribute vec2 vert;
    uniform mat4 V;
    uniform mat4 M;
    uniform mat4 P;
    uniform sampler2D heightmap;
    uniform sampler2D detail;
    uniform float heightmap_scale;
    uniform float detail_scale;
    uniform float detail_height;
    uniform float y_scale;
    uniform vec3 light_dir;
    varying vec3 w_pos;
    varying vec3 v_pos;
    varying vec3 v_color;
    varying vec3 v_light_dir;
    void main() {
        vec2 tpos = (V * vec4(vert.x, 0, vert.y, 1)).xz;
        vec2 tpos_main = heightmap_scale * tpos;
        vec2 tpos_detail = detail_scale * tpos;
        vec4 main_sample = texture2D(heightmap, tpos_main);
        vec4 detail_sample = texture2D(detail, tpos_detail);
        float height = main_sample.a + detail_sample.a * detail_height;
        v_color = main_sample.rgb;
        w_pos = vec3(tpos.x, main_sample.a * y_scale, tpos.y);
        v_pos = (M * vec4(vert.x, height, -vert.y, 1.0)).xyz;
        v_light_dir = normalize((M * V * vec4(light_dir, 0.0)).xyz); // XXX should compute outside shader
        gl_Position = P * vec4(v_pos, 1.0);
        gl_PointSize = 2.0;
    }
]]

local terrain_fshader = [[
    #extension GL_OES_standard_derivatives : enable
    precision highp float;
    uniform vec3 fog_color;
    uniform float fog_dist;
    uniform vec3 diffuse;
    uniform vec3 ambient;
    uniform vec3 emission;
    uniform vec3 specular;
    uniform float shininess;
    uniform sampler2D detail;
    //uniform sampler2D side;
    uniform float detail_scale;
    varying vec3 w_pos;
    varying vec3 v_pos;
    varying vec3 v_color;
    varying vec3 v_light_dir;

    vec3 compute_w_normal() {
        vec3 p1 = dFdx(w_pos);
        vec3 p2 = dFdy(w_pos);
        return normalize(cross(p1, p2));
    }

    vec3 compute_normal() {
        vec3 p1 = dFdx(v_pos);
        vec3 p2 = dFdy(v_pos);
        return normalize(cross(p1, p2));
    }

    void main() {
        float fog_r = 1.0 - pow(gl_FragCoord.z, fog_dist);
        vec3 norm = compute_normal();
        float diffc = dot(v_light_dir, norm);

        //vec3 blending = (abs(compute_w_normal()) - 0.2) * 7.0;
        //blending = normalize(max(blending, 0.0)); // Force weights to sum to 1.0
        //float b = (blending.x + blending.y + blending.z);
        //blending /= vec3(b, b, b);
        vec4 t_pos = vec4(w_pos, 1.0);
        vec4 yaxis = texture2D(detail, t_pos.xz * detail_scale);
        vec4 tex;
        //if (blending.y < 0.2) {
        //    vec4 xaxis = texture2D(side, vec2(t_pos.z, t_pos.y) * 0.02);
        //    vec4 zaxis = texture2D(side, vec2(t_pos.x, t_pos.y) * 0.02);
        //    tex = xaxis * blending.x + yaxis * blending.y + zaxis * blending.z;
        //} else {
            tex = yaxis;
        //}

        vec3 spec = vec3(0.0);
        vec3 diff = vec3(0.0);
        if (diffc > 0.0) {
            diff = diffuse * diffc;
            spec = specular * pow(max(0.0, dot(normalize(-v_pos), reflect(-v_light_dir, norm))), shininess);
        }
        vec3 color = v_color * tex.rgb * (diff + ambient + spec) + emission;

        gl_FragColor = vec4(mix(fog_color, color, fog_r), 1.0);
    }
]]

local terrain_shader = am.program(terrain_vshader, terrain_fshader)

local readback_buffer = am.buffer(4)
local readback_view = readback_buffer:view("ubyte", 0, 1)
local readback_texture = am.texture2d(am.image_buffer(readback_buffer, 1))
local readback_framebuffer = am.framebuffer(readback_texture)
local readback_vshader = [[
    precision highp float;
    attribute vec2 vert;
    void main() {
        gl_Position = vec4(vert, 0.0, 1.0);
        gl_PointSize = 2.0;
    }
]]
local readback_fshader = [[
    precision mediump float;
    uniform vec2 uv;
    uniform sampler2D floor_texture;
    uniform sampler2D ceiling_texture;
    void main() {
        vec4 floor_sample = texture2D(floor_texture, uv);
        vec4 ceiling_sample = texture2D(ceiling_texture, uv);
        gl_FragColor = vec4(floor_sample.a, ceiling_sample.a, 0, 0);
    }
]]
local readback_shader = am.program(readback_vshader, readback_fshader)
local readback_verts = am.vec2_array{0, 0}

local
function create_mesh(width, depth, near_clip, far_clip, fov)
    local num_verts = (width + 1) * (depth + 1)
    local verts = {}
    local z_dist = far_clip - near_clip
    local k = 1
    local h = 1
    local l = 1
    local indices = {}

    for j = 0, depth do
        local t = j/depth
        t = t ^ 3.5
        local z = t * z_dist + near_clip
        local z4 = 4 * z
        local w2 = width/2
        local nw2 = -w2
        for i = -width/2, width/2 do
            local x
            if i == nw2 then
                x = -10000
            elseif i == w2 then
                x = 10000
            else
                x = i / w2 * z4
            end
            verts[k] = x
            verts[k+1] = z
            if j < depth and i < w2 then
                indices[h+0] = l
                indices[h+1] = l + width + 1
                indices[h+2] = l + 1
                indices[h+3] = l + 1
                indices[h+4] = l + width + 1
                indices[h+5] = l + width + 2
                h = h + 6
            end
            k = k + 2
            l = l + 1
        end
    end
    return 
        am.bind{vert = am.vec2_array(verts)}
        ^ am.draw("triangles", am.uint_elem_array(indices))
end

function terrain.create(in_settings)
    local shoulder_height = 8
    local head_height = 1
    local walk_speed = 60
    local strafe_speed = walk_speed
    local gravity = -100
    local jump_speed = 50
    local barrier_height = 3
    local lookahead = 2

    local start_pos = in_settings.start_pos or vec2(0.25)
    local floor_texture = in_settings.floor_texture
    local floor_detail = in_settings.floor_detail_texture
    local ceiling_texture = in_settings.ceiling_texture
    local ceiling_detail = in_settings.ceiling_detail_texture
    local floor_side_texture = in_settings.floor_side_texture
    local ceiling_side_texture = in_settings.ceiling_side_texture

    local width = 800
    local depth = 600
    local near_clip = 1
    local far_clip = 700
    local floor_heightmap_scale = 0.001
    local ceiling_heightmap_scale = 0.001
    local floor_detail_scale = 0.05
    local ceiling_detail_scale = 0.05
    local floor_y_scale = 100.0
    local ceiling_y_scale = 100.0
    local floor_y_offset = -100.0
    local ceiling_y_offset = -90.0
    local fog_color = vec3(0.6, 0.05, 0.01)
    local fog_dist = 1000
    local ambient = vec3(0.3)
    local diffuse = vec3(0.7)
    local emission = vec3(0)
    local specular = vec3(0)
    local shininess = 1
    local detail_height = 0.03
    local aspect = win.width / win.height

    local mesh_node = create_mesh(width, depth, near_clip, far_clip)

    local floor_node =
        am.cull_face("cw")
        ^ am.bind{
            light_dir = vec3(0),
            detail_scale = floor_detail_scale,
            heightmap_scale = floor_heightmap_scale,
            y_scale = floor_y_scale,
            detail = floor_detail,
            heightmap = floor_texture,
            --side = floor_side_texture,
        }
        ^ am.translate("M", vec3(0, floor_y_offset, 0))
        ^ am.scale("M", vec3(1, floor_y_scale, 1))
        ^ am.group():tag"mesh_parent"
        ^ mesh_node

    local ceiling_node = 
        am.cull_face("ccw")
        ^ am.bind{
            light_dir = vec3(0),
            detail_scale = ceiling_detail_scale,
            heightmap_scale = ceiling_heightmap_scale,
            y_scale = ceiling_y_scale,
            detail = ceiling_detail,
            heightmap = ceiling_texture,
            --side = ceiling_side_texture,
        }
        ^ am.translate("M", vec3(0, ceiling_y_offset, 0))
        ^ am.scale("M", vec3(1, ceiling_y_scale, 1))
        ^ am.group():tag"mesh_parent"
        ^ mesh_node

    local scene = 
        am.viewport(0, 0, 0, 0)
        ^ am.use_program(terrain_shader)
        ^ am.bind{
            V = mat4(1),
            fog_color = fog_color,
            fog_dist = fog_dist,
            detail_height = detail_height,
            P = math.perspective(math.rad(70), aspect, near_clip, far_clip),
            M = mat4(1),
            t = 0,
            ambient = ambient,
            diffuse = diffuse,
            emission = emission,
            specular = specular,
            shininess = shininess,
        }
        ^ am.rotate("M", quat(0, vec3(-1, 0, 0))):tag"pitch"
        ^ am.translate("M", vec3(0)):tag"ypos"
        ^ {
            floor_node,
            ceiling_node,
        }

    local uv_readback_node = 
        am.bind{
            vert = readback_verts,
            uv = vec2(0),
        }
        ^ am.draw("points")
    local readback_node = 
        am.use_program(readback_shader)
        ^ am.bind{
            floor_texture = floor_texture,
            ceiling_texture = ceiling_texture,
        }
        ^ uv_readback_node

    local pitch = 0
    local facing = 0
    local pos = start_pos / floor_heightmap_scale
    local up = vec3(0, 1, 0)
    local y_pos = 0
    local y_speed = 0
    local on_ground = false
    local floor_y = 255
    local ceiling_y = 255

    local state = {
        pos = start_pos,
        pos_abs = start_pos,
        node = scene,
        facing = facing,
        readback_node = readback_node,
        ceiling_node = ceiling_node,
        floor_node = floor_node,
    }

    local settings_updated = true
    local start_pos_changed = false

    scene:action(function()
        if state.paused and not start_pos_changed then
            return
        end
        start_pos_changed = false

        local c = math.cos
        local s = math.sin
        local pi = math.pi
        local forward = vec2(c(facing), s(facing))
        --log("facing = %g, forward = %s, pos = %s",
        --    facing > 0 and math.deg(facing) or math.deg(facing) + 360,
        --    forward,
        --    pos)
        local left = vec2(c(facing+pi/2), s(facing+pi/2))
        local new_pos = pos
        if win:key_down("w") or win:key_down("up") --[[or win:mouse_down"left"]] then
            new_pos = new_pos + forward * walk_speed * am.delta_time
        elseif win:key_down("s") or win:key_down("down") then
            new_pos = new_pos - forward * walk_speed * am.delta_time
        end
        if win:key_down("a") or win:key_down("left") then
            new_pos = new_pos + left * strafe_speed * am.delta_time
        elseif win:key_down("d") or win:key_down("right") then
            new_pos = new_pos - left * strafe_speed * am.delta_time
        end

        local floor_pos = new_pos + lookahead * forward
        local lookup_pos = vec2(floor_pos.x, floor_pos.y) * floor_heightmap_scale
        uv_readback_node.uv = lookup_pos
        readback_framebuffer:render(readback_node)
        readback_framebuffer:read_back()
        local new_floor_y = ((readback_view[1]/255)*floor_y_scale + floor_y_offset) + shoulder_height
        local new_ceiling_y = ((readback_view[2]/255)*ceiling_y_scale + ceiling_y_offset) - head_height

        if settings_updated or state.noclip or new_floor_y - y_pos < barrier_height and new_ceiling_y - new_floor_y > 0 then
            pos = new_pos
            floor_y = new_floor_y
            ceiling_y = new_ceiling_y
            settings_updated = false
        end

        -- XXX why do we need minus forward here?
        local V = math.lookat(vec3(pos.x, 0, pos.y), vec3(pos.x - forward.x, 0, pos.y - forward.y), up)
        scene"bind".V = math.inverse(V)
        local mouse_delta = win:mouse_norm_delta()
        facing = facing - mouse_delta.x * pi
        pitch = math.clamp(pitch + mouse_delta.y, -0.80, 0.80)
        scene"pitch".rotation = quat(pitch, vec3(-1, 0, 0))

        scene"bind".t = am.frame_time

        if on_ground and win:key_pressed("space") then
            y_speed = jump_speed
            on_ground = false
        end
        y_speed = y_speed + gravity * am.delta_time
        y_pos = y_pos + y_speed * am.delta_time
        if y_pos < floor_y then
            y_pos = floor_y
            y_speed = 0
            on_ground = true
        elseif not state.noclip and y_pos > ceiling_y then
            y_pos = ceiling_y
            y_speed = 0
        end
        scene"ypos".position = vec3(0, -y_pos, 0)

        --log(table.tostring(am.perf_stats()))

        local pos2 = pos * floor_heightmap_scale
        local fract = math.fract(pos2)
        local whole = pos2 - fract
        if whole.x % 2 == 1 then
            fract = fract{x = 1-fract.x}
        end
        if whole.y % 2 == 1 then
            fract = fract{y = 1-fract.y}
        end
        state.pos = fract
        state.pos_abs = pos2
        state.facing = facing

        --scene"bind".light_dir = math.normalize(vec3(math.sin(am.frame_time) * 2, math.cos(am.frame_time) * 2, 10))
        local light_dir = math.normalize(vec3(0.4, 0.01, 1.0))
        ceiling_node"bind".light_dir = light_dir; -- because we're rendering other side of face
        floor_node"bind".light_dir = light_dir;
        --scene"bind".light_dir = (M * math.inverse(V) * vec4(light_dir, 0)).xyz;
    end)

    function state:update_layout(layout)
        local w = win.pixel_width - layout.left
        local h = win.pixel_height - layout.bottom
        aspect = w / h
        scene"bind".P = math.perspective(math.rad(70), aspect, near_clip, far_clip)
        scene"viewport".left = layout.left
        scene"viewport".bottom = layout.bottom
        scene"viewport".width = w
        scene"viewport".height = h
    end

    function state:update_settings(settings)
        state.settings = settings

        settings.floor_heightmap_scale = settings.floor_heightmap_scale or 0.001
        settings.ceiling_heightmap_scale = settings.ceiling_heightmap_scale or 0.001
        settings.floor_detail_scale = settings.floor_detail_scale or 0.05
        settings.ceiling_detail_scale = settings.ceiling_detail_scale or 0.05
        settings.floor_y_scale = settings.floor_y_scale or 100
        settings.ceiling_y_scale = settings.ceiling_y_scale or 100
        settings.floor_y_offset = settings.floor_y_offset or -100
        settings.ceiling_y_offset = settings.ceiling_y_offset or -90
        settings.fog_color = settings.fog_color or vec3(0)
        settings.fog_dist = settings.fog_dist or 1000
        settings.detail_height = settings.detail_height or 0.03
        settings.ambient = settings.ambient or vec3(0.3)
        settings.diffuse = settings.diffuse or vec3(0.7)
        settings.emission = settings.emission or vec3(0)
        settings.specular = settings.specular or vec3(0)
        settings.shininess = settings.shininess or 1
        settings.start_pos = settings.start_pos or vec2(0.25)
        settings.width = settings.width or 800
        settings.depth = settings.depth or 600
        settings.filter = settings.filter or "linear"
        settings.walk_speed = settings.walk_speed or 60
        settings.wireframe = settings.wireframe or false
        settings.noclip = settings.noclip or false

        floor_texture = settings.floor_texture
        floor_detail = settings.floor_detail_texture
        ceiling_texture = settings.ceiling_texture
        ceiling_detail = settings.ceiling_detail_texture
        --floor_side_texture = settings.floor_side_texture
        --ceiling_side_texture = settings.ceiling_side_texture

        floor_texture.minfilter = settings.filter
        floor_texture.magfilter = settings.filter
        floor_detail.minfilter = settings.filter
        floor_detail.magfilter = settings.filter
        ceiling_texture.minfilter = settings.filter
        ceiling_texture.magfilter = settings.filter
        ceiling_detail.minfilter = settings.filter
        ceiling_detail.magfilter = settings.filter

        floor_node"bind".heightmap = floor_texture
        floor_node"bind".detail = floor_detail
        --floor_node"bind".side = floor_side_texture
        ceiling_node"bind".heightmap = ceiling_texture
        ceiling_node"bind".detail = ceiling_detail
        --ceiling_node"bind".side = ceiling_side_texture
        readback_node"bind".floor_texture = floor_texture
        readback_node"bind".ceiling_texture = ceiling_texture

        floor_heightmap_scale = settings.floor_heightmap_scale
        ceiling_heightmap_scale = settings.ceiling_heightmap_scale
        floor_detail_scale = settings.floor_detail_scale
        ceiling_detail_scale = settings.ceiling_detail_scale
        floor_node"bind".heightmap_scale = floor_heightmap_scale
        floor_node"bind".detail_scale = floor_detail_scale
        ceiling_node"bind".heightmap_scale = ceiling_heightmap_scale
        ceiling_node"bind".detail_scale = ceiling_detail_scale

        floor_y_scale = settings.floor_y_scale
        ceiling_y_scale = settings.ceiling_y_scale
        floor_y_offset = settings.floor_y_offset
        ceiling_y_offset = settings.ceiling_y_offset
        floor_node"scale".scale = vec3(1, floor_y_scale, 1)
        floor_node"bind".y_scale = floor_y_scale
        ceiling_node"scale".scale = vec3(1, ceiling_y_scale, 1)
        ceiling_node"bind".y_scale = ceiling_y_scale
        floor_node"translate".position = vec3(0, floor_y_offset, 0)
        ceiling_node"translate".position = vec3(0, ceiling_y_offset, 0)

        detail_height = settings.detail_height
        scene"bind".detail_height = detail_height

        fog_color = settings.fog_color
        scene"bind".fog_color = fog_color
        win.clear_color = vec4(fog_color, 1)
        fog_dist = settings.fog_dist
        scene"bind".fog_dist = fog_dist

        ambient = settings.ambient
        scene"bind".ambient = ambient
        diffuse = settings.diffuse
        scene"bind".diffuse = diffuse
        emission = settings.emission
        scene"bind".emission = emission
        specular = settings.specular
        scene"bind".specular = specular
        shininess = settings.shininess
        scene"bind".shininess = shininess

        if math.distance(start_pos, settings.start_pos) > 0.001 then
            start_pos = settings.start_pos
            pos = start_pos / floor_heightmap_scale
            state.pos = start_pos
            start_pos_changed = true
        end

        if settings.width ~= width or settings.depth ~= depth then
            width = settings.width
            depth = settings.depth
            mesh_node = create_mesh(width, depth, near_clip, far_clip)
            floor_node"mesh_parent":remove_all():append(mesh_node)
            ceiling_node"mesh_parent":remove_all():append(mesh_node)
            collectgarbage()
            collectgarbage()
        end

        if settings.wireframe then
            mesh_node"draw".primitive = "lines"
            win.clear_color = vec4(0)
            scene"bind".fog_color = vec3(0)
            scene"bind".fog_dist = 1000
            scene"bind".ambient = vec3(0)
            scene"bind".diffuse = vec3(0)
            scene"bind".specular = vec3(0)
            scene"bind".emission = vec3(0, 1, 0)
        else
            mesh_node"draw".primitive = "triangles"
            win.clear_color = vec4(fog_color, 1)
            scene"bind".fog_color = fog_color
            scene"bind".fog_dist = fog_dist
            scene"bind".ambient = ambient
            scene"bind".diffuse = diffuse
            scene"bind".emission = emission
            scene"bind".specular = specular
        end

        walk_speed = settings.walk_speed
        strafe_speed = walk_speed

        state.noclip = settings.noclip

        settings_updated = true
    end

    function state:reset_pos()
        pos = start_pos / floor_heightmap_scale
        state.pos = start_pos
        start_pos_changed = true
    end

    state:update_settings(in_settings)

    return state
end

return terrain
