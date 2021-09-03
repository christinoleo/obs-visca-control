obs = obslua
Visca = require("libvisca")

plugin_info = {
    name = "Visca Camera Control",
    version = "1.3",
    url = "https://github.com/vwout/obs-visca-control",
    description = "Camera control via Visca over IP",
    author = "vwout"
}

plugin_settings = {}
plugin_def = {}
plugin_def.id = "Visca_Control"
plugin_def.type = obs.OBS_SOURCE_TYPE_INPUT
plugin_def.output_flags = bit.bor(obs.OBS_SOURCE_CUSTOM_DRAW)
plugin_data = {}
plugin_data.debug = false
plugin_data.active_scene = nil
plugin_data.preview_scene = nil
plugin_data.connections = {}
plugin_data.hotkeys = {}

local previous_actions = {}

local actions = {
    Camera_Off = 0,
    Camera_On  = 1,
    Preset_Recal = 2,
    Pan_Left = 3,
    Pan_Right = 4,
    Tilt_Up = 5,
    Tilt_Down = 6,
    Zoom_In = 7,
    Zoom_Out = 8,
    Preset_1 = 9,
    Preset_2 = 10,
    Preset_3 = 11,
    Preset_4 = 12,
    Preset_5 = 13,
    Preset_6 = 14,
    Preset_7 = 15,
    Preset_8 = 16,
    Preset_9 = 17,
    Animate = 18,
}

local action_active = {
    Program = 1,
    Preview = 2,
    Always = 3,
}


local function log(fmt, ...)
    if plugin_data.debug then
        local info = debug.getinfo(2, "nl")
        local func = info.name or "?"
        local line = info.currentline
        print(string.format("%s (%d): %s", func, line, string.format(fmt, unpack(arg or {...}))))
    end
end

local function create_camera_controls(props, camera_id, settings)
    local cams = obs.obs_properties_get(props, "cameras")
    if cams then
        local cam_prop_prefix = string.format("cam_%d_", camera_id)
        local cam_name_suffix = string.format(" (cam %d)", camera_id)
        
        local cam_name = obs.obs_data_get_string(settings, cam_prop_prefix .. "name")
        if #cam_name == 0 then
            cam_name = string.format("Camera %d", camera_id)
        end
        obs.obs_property_list_add_int(cams, cam_name, camera_id)
        
        local prop_name = obs.obs_properties_get(props, cam_prop_prefix .. "name")
        if prop_name == nil then
            obs.obs_properties_add_text(props, cam_prop_prefix .. "name", "Name" .. cam_name_suffix, obs.OBS_TEXT_DEFAULT)
            obs.obs_data_set_default_string(plugin_settings, cam_prop_prefix .. "name", cam_name)
        end
        local prop_address = obs.obs_properties_get(props, cam_prop_prefix .. "address")
        if prop_address == nil then
            obs.obs_properties_add_text(props, cam_prop_prefix .. "address", "IP Address" .. cam_name_suffix, obs.OBS_TEXT_DEFAULT)
        end
        local prop_port = obs.obs_properties_get(props, cam_prop_prefix .. "port")
        if prop_port == nil then
            obs.obs_properties_add_int(props, cam_prop_prefix .. "port", "UDP Port" .. cam_name_suffix, 1025, 65535, 1)
            obs.obs_data_set_default_int(plugin_settings, cam_prop_prefix .. "port", Visca.default_port)
        end
    	local prop_mode = obs.obs_properties_add_list(props, cam_prop_prefix .. "mode", "Mode" .. cam_name_suffix, obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    	obs.obs_property_list_add_int(prop_mode, "Generic", Visca.modes.generic)
	    obs.obs_property_list_add_int(prop_mode, "PTZOptics", Visca.modes.ptzoptics)
        obs.obs_data_set_default_int(plugin_settings, cam_prop_prefix .. "mode", Visca.modes.generic)
        local prop_presets = obs.obs_properties_get(props, cam_prop_prefix .. "presets")
        if prop_presets == nil then
            prop_presets = obs.obs_properties_add_editable_list(props, cam_prop_prefix .. "presets", "Presets" .. cam_name_suffix, obs.OBS_EDITABLE_LIST_TYPE_STRINGS, "", "")
        end
        obs.obs_property_set_modified_callback(prop_presets, prop_presets_validate)
    end
end

local function do_cam_action_start(camera_id, camera_action, action_arg, scene_animation_direction, scene_animation_speed)
    local cam_prop_prefix = string.format("cam_%d_", camera_id)
    local camera_address = obs.obs_data_get_string(plugin_settings, cam_prop_prefix .. "address")
    local camera_port = obs.obs_data_get_int(plugin_settings, cam_prop_prefix .. "port")
    local camera_mode = obs.obs_data_get_int(plugin_settings, cam_prop_prefix .. "mode")

    log("Start cam %d @%s action %d (arg %d, anim %d, speed %f)", camera_id, camera_address, camera_action, action_arg or 0, scene_animation_direction or 0, scene_animation_speed or 0)
    local connection = plugin_data.connections[camera_id]

    -- Force close connection before sending On-command to prevent usage of a dead connection
    if connection ~= nil and camera_action == actions.Camera_On then
        connection.close()
        connection = nil
        plugin_data.connections[camera_id] = nil
    end

    if connection == nil then
        local connection_error = ""
        connection, connection_error = Visca.connect(camera_address, camera_port)
        if connection then
            if camera_mode then
                connection.set_mode(camera_mode)
            end
            plugin_data.connections[camera_id] = connection
        else
            log(connection_error)
        end
    end

    if connection then
        if camera_action == actions.Camera_Off then
            connection.Cam_Power(false)

            -- Force close connection after sending Off-command.
            connection.close()
            plugin_data.connections[camera_id] = nil
            return
        elseif camera_action == actions.Camera_On then
            connection.Cam_Power(true)
        elseif camera_action == actions.Preset_Recal then
            connection.Cam_Preset_Recall(action_arg)
        elseif camera_action == actions.Pan_Left then
            connection.Cam_PanTilt(Visca.PanTilt_directions.left, 3)
        elseif camera_action == actions.Pan_Right then
            connection.Cam_PanTilt(Visca.PanTilt_directions.right, 3)
        elseif camera_action == actions.Tilt_Up then
            connection.Cam_PanTilt(Visca.PanTilt_directions.up, 3)
        elseif camera_action == actions.Tilt_Down then
            connection.Cam_PanTilt(Visca.PanTilt_directions.down, 3)
        elseif camera_action == actions.Zoom_In then
            connection.Cam_Zoom_Tele()
        elseif camera_action == actions.Zoom_Out then
            connection.Cam_Zoom_Wide()
        elseif camera_action == actions.Preset_1 then
            connection.Cam_Preset_Recall(0)
        elseif camera_action == actions.Preset_2 then
            connection.Cam_Preset_Recall(1)
        elseif camera_action == actions.Preset_3 then
            connection.Cam_Preset_Recall(2)
        elseif camera_action == actions.Preset_4 then
            connection.Cam_Preset_Recall(3)
        elseif camera_action == actions.Preset_5 then
            connection.Cam_Preset_Recall(4)
        elseif camera_action == actions.Preset_6 then
            connection.Cam_Preset_Recall(5)
        elseif camera_action == actions.Preset_7 then
            connection.Cam_Preset_Recall(6)
        elseif camera_action == actions.Preset_8 then
            connection.Cam_Preset_Recall(7)
        elseif camera_action == actions.Preset_9 then
            connection.Cam_Preset_Recall(8)
        elseif camera_action == actions.Animate then
            connection.Cam_PanTilt(scene_animation_direction, scene_animation_speed)
        end
    end
end

local function do_cam_action_stop(camera_id, camera_action, action_arg)
    local cam_prop_prefix = string.format("cam_%d_", camera_id)
    local camera_address = obs.obs_data_get_string(plugin_settings, cam_prop_prefix .. "address")
    local camera_port = obs.obs_data_get_int(plugin_settings, cam_prop_prefix .. "port")
    local camera_mode = obs.obs_data_get_int(plugin_settings, cam_prop_prefix .. "mode")

    log("Stop cam %d @%s action %d (arg %d)", camera_id, camera_address, camera_action or 0, action_arg or 0)
    local connection = plugin_data.connections[camera_id]
    if connection == nil then
        local connection_error = ""
        connection, connection_error = Visca.connect(camera_address, camera_port)
        if connection then
            if camera_mode then
                connection.set_mode(camera_mode)
            end
            plugin_data.connections[camera_id] = connection
        else
            log(connection_error)
        end
    end

    if connection then
        if camera_action == actions.Pan_Left then
            connection.Cam_PanTilt(Visca.PanTilt_directions.stop)
        elseif camera_action == actions.Pan_Right then
            connection.Cam_PanTilt(Visca.PanTilt_directions.stop)
        elseif camera_action == actions.Tilt_Up then
            connection.Cam_PanTilt(Visca.PanTilt_directions.stop)
        elseif camera_action == actions.Tilt_Down then
            connection.Cam_PanTilt(Visca.PanTilt_directions.stop)
        elseif camera_action == actions.Zoom_In then
            connection.Cam_Zoom_Stop()
        elseif camera_action == actions.Zoom_Out then
            connection.Cam_Zoom_Stop()
        elseif camera_action == actions.Animate then
            connection.Cam_PanTilt(Visca.PanTilt_directions.stop)
        end
    end
end

local function cb_camera_hotkey(pressed, hotkey_data)
    if pressed then
        do_cam_action_start(hotkey_data.camera_id, hotkey_data.action)
    else
        do_cam_action_stop(hotkey_data.camera_id, hotkey_data.action)
    end
end

function script_description()
    return "<b>" .. plugin_info.description .. "</b><br>" ..
           "Version: " .. plugin_info.version .. "<br>" ..
           "<a href=\"" .. plugin_info.url .. "\">" .. plugin_info.url .. "</a><br><br>" ..
           "Usage:<br>" ..
           "To add a preset in the list, use one the following naming conventions:<ul>" ..
           "<li>&lt;name&gt;&lt;separator&gt;&lt;preset id&gt;, e.g. 'Stage: 6'</li>" .. 
           "<li>&lt;preset id&gt;&lt;separator&gt;&lt;name&gt;, e.g. '5 = Pastor'</li>" ..
           "</ul>where &lt;separator&gt; is one of ':', '=' or '-'."
end

function script_update(settings)
    plugin_settings = settings
end

function script_save(settings)
    for _,hotkey in pairs(plugin_data.hotkeys) do
        local a = obs.obs_hotkey_save(hotkey.id)
        obs.obs_data_set_array(settings, hotkey.name .. "_hotkey", a)
        obs.obs_data_array_release(a)
    end
end

function script_load(settings)
    local hotkey_actions = {
        { name = "pan_left", descr = "Pan Left", action = actions.Pan_Left },
        { name = "pan_right", descr = "Pan Right", action = actions.Pan_Right},
        { name = "tilt_up", descr = "Tilt Up", action = actions.Tilt_Up},
        { name = "tilt_down", descr = "Tilt Down", action = actions.Tilt_Down},
        { name = "zoom_in", descr = "Zoom In", action = actions.Zoom_In},
        { name = "zoom_out", descr = "Zoom Out", action = actions.Zoom_Out },
        { name = "preset_1", descr = "Preset 1", action = actions.Preset_1 },
        { name = "preset_2", descr = "Preset 2", action = actions.Preset_2 },
        { name = "preset_3", descr = "Preset 3", action = actions.Preset_3 },
        { name = "preset_4", descr = "Preset 4", action = actions.Preset_4 },
        { name = "preset_5", descr = "Preset 5", action = actions.Preset_5 },
        { name = "preset_6", descr = "Preset 6", action = actions.Preset_6 },
        { name = "preset_7", descr = "Preset 7", action = actions.Preset_7 },
        { name = "preset_8", descr = "Preset 8", action = actions.Preset_8 },
        { name = "preset_9", descr = "Preset 9", action = actions.Preset_9 },
    }

    local num_cameras = obs.obs_data_get_int(settings, "num_cameras")
    for camera_id = 1,num_cameras do
        local cam_prop_prefix = string.format("cam_%d_", camera_id)
        local cam_name = obs.obs_data_get_string(settings, cam_prop_prefix .. "name")
        if #cam_name == 0 then
            cam_name = string.format("Camera %d", camera_id)
        end

        for _,v in pairs(hotkey_actions) do
            local hotkey_name = cam_prop_prefix .. v.name
            local hotkey_id = obs.obs_hotkey_register_frontend(hotkey_name, v.descr .. " " .. cam_name, function(pressed)
                    cb_camera_hotkey(pressed, { name = hotkey_name, camera_id = camera_id, action = v.action })
                end)

            local a = obs.obs_data_get_array(settings, hotkey_name .. "_hotkey")
            obs.obs_hotkey_load(hotkey_id, a)
            obs.obs_data_array_release(a)

            table.insert(plugin_data.hotkeys, {
                name = hotkey_name,
                id = hotkey_id,
                camera_id = camera_id,
                action = v.action
            })
        end
    end
end

function script_properties()
    local props = obs.obs_properties_create()
    
    local num_cams = obs.obs_properties_add_int(props, "num_cameras", "Number of cameras", 0, 8, 1)
    obs.obs_property_set_modified_callback(num_cams, prop_num_cams)
    
    local num_cameras = obs.obs_data_get_int(plugin_settings, "num_cameras")
    log("num_cameras %d", num_cameras)
    
    local cams = obs.obs_properties_add_list(props, "cameras", "Camera", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    for camera_id = 1, num_cameras do
        create_camera_controls(props, camera_id, plugin_settings)
    end
    
    local debug = obs.obs_properties_add_bool(props, "debug", "debug log (needs refresh)")
    
    obs.obs_property_set_modified_callback(cams, prop_set_attrs_values)

    return props
end

function prop_num_cams(props, property, settings)
    local cam_added = false
    
    local num_cameras = obs.obs_data_get_int(plugin_settings, "num_cameras")
    log("num_cameras %d", num_cameras)
    local cams = obs.obs_properties_get(props, "cameras")
    if cams then
        local camera_count = obs.obs_property_list_item_count(cams)
        if num_cameras > camera_count then
            for camera_id = camera_count+1, num_cameras do
                create_camera_controls(props, camera_id, settings)
            end
            cam_added = true
        end
    end
    
    return cam_added
end

function prop_set_attrs_values(props, property, settings)
    local changed = false
    local num_cameras = obs.obs_data_get_int(plugin_settings, "num_cameras")
    local cam_idx = obs.obs_data_get_int(settings, "cameras")
    if cnt == 0 then
        cam_idx = 0
    end
    
    for camera_id = 1, num_cameras do
        local visible = cam_idx == camera_id
        log("%d %d %d", camera_id, cam_idx, visible and 1 or 0)
        
        local cam_prop_prefix = string.format("cam_%d_", camera_id)

        local cam_props = {"name", "address", "port", "mode", "presets", "preset_info"}
        for _,cam_prop_name in pairs(cam_props) do
            local cam_prop = obs.obs_properties_get(props, cam_prop_prefix .. cam_prop_name)
            if cam_prop then
                if obs.obs_property_visible(cam_prop) ~= visible then
                    obs.obs_property_set_visible(cam_prop, visible)
                    changed = true
                end
            end
        end
    end

    plugin_data.debug = obs.obs_data_get_bool(plugin_settings, "debug")
    
    return changed
end

local function parse_preset_value(preset_value)
    local preset_name = nil
    local preset_id = nil
    local regex_patterns = {
        "^(.+)%s*[:=-]%s*(%d+)$",
        "^(%d+)%s*[:=-]%s*(.+)$"
    }
    
    for _,pattern in pairs(regex_patterns) do
        local v1 = nil
        local v2 = nil
        v1,v2 = string.match(preset_value, pattern)
        log("match '%s', '%s'", tostring(v1), tostring(v2))
        if (v1 ~= nil) and (v2 ~= nil) then
            if (tonumber(v1) == nil) and (tonumber(v2) ~= nil) then
                preset_name = v1
                preset_id = tonumber(v2)
                break
            elseif (tonumber(v2) == nil) and (tonumber(v1) ~= nil) then
                preset_name = v2
                preset_id = tonumber(v1)
                break
            end
        end
    end
    
    return preset_name, preset_id
end

function prop_presets_validate(props, property, settings)
    local presets = obs.obs_data_get_array(settings, obs.obs_property_name(property))
    local num_presets = obs.obs_data_array_count(presets)
    log("prop_presets_validate %s %d", obs.obs_property_name(property), num_presets)

    if num_presets > 0 then
        for i = 0, num_presets-1 do
            local preset = obs.obs_data_array_item(presets, i)
            --log(obs.obs_data_get_json(preset))
            local preset_value = obs.obs_data_get_string(preset, "value")
            --log("check %s", preset_value)
            
            local preset_name, preset_id = parse_preset_value(preset_value)
            if (preset_name == nil) or (preset_id == nil) then
                print("Warning: preset '" .. preset_value .. "' has an unsupported syntax and cannot be used.")
            end
        end
    end
    
    obs.obs_data_array_release(presets)
end

plugin_def.get_name = function()
    return plugin_info.name
end

plugin_def.create = function(settings, source)
    local data = {}
    local source_sh = obs.obs_source_get_signal_handler(source)
    obs.obs_frontend_add_event_callback(fe_callback)
	obs.signal_handler_connect(source_sh, "deactivate", signal_on_deactivate)
	obs.signal_handler_connect(source_sh, "activate", signal_on_activate)
    return data
end

plugin_def.destroy = function(source)
    for camera_id, connection in pairs(plugin_data.connections) do
        if connection ~= nil then
            connection.close()
            plugin_data.connections[camera_id] = nil
        end
    end
    plugin_data.connections = {}
end

plugin_def.get_properties = function (data)
	local props = obs.obs_properties_create()
    
    local num_cameras = obs.obs_data_get_int(plugin_settings, "num_cameras")
	local prop_camera = obs.obs_properties_add_list(props, "scene_camera", "Camera:", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)

	local prop_action = obs.obs_properties_add_list(props, "scene_action", "Action:", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	obs.obs_property_list_add_int(prop_action, "Camera Off", actions.Camera_Off)
	obs.obs_property_list_add_int(prop_action, "Camera On", actions.Camera_On)
	obs.obs_property_list_add_int(prop_action, "Preset Recall", actions.Preset_Recal)
	obs.obs_property_list_add_int(prop_action, "Animation", actions.Animate)

    
	local prop_animation = obs.obs_properties_add_list(props, "scene_animation_direction", "Animation Direction:", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	obs.obs_property_list_add_int(prop_animation, "None", 0)
    for _type, _number in pairs(Visca.PanTilt_directions) do
        obs.obs_property_list_add_int(prop_animation, _type, _number)
    end
	local prop_animation_speed = obs.obs_properties_add_float_slider(props, "scene_animation_speed", "Animation Speed:", Visca.limits.PAN_MIN_SPEED, Visca.limits.PAN_MAX_SPEED, 0.1)
    
    for camera_id = 1, num_cameras do
        local cam_prop_prefix = string.format("cam_%d_", camera_id)
        local cam_name_suffix = string.format(" (cam %d)", camera_id)

        local cam_name = obs.obs_data_get_string(plugin_settings, cam_prop_prefix .. "name")
        if #cam_name == 0 then
            cam_name = string.format("Camera %d", camera_id)
        end
        obs.obs_property_list_add_int(prop_camera, cam_name, camera_id)
        
        local prop_presets = obs.obs_properties_add_list(props, "scene_" .. cam_prop_prefix .. "preset", "Presets" .. cam_name_suffix, obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
        local presets = obs.obs_data_get_array(plugin_settings, cam_prop_prefix .. "presets")
        local num_presets = obs.obs_data_array_count(presets)
        log("get_properties %s %d", cam_prop_prefix .. "preset", num_presets)

        if num_presets > 0 then
            local first_preset = true
            for i = 0, num_presets-1 do
                local preset = obs.obs_data_array_item(presets, i)
                --log(obs.obs_data_get_json(preset))
                local preset_value = obs.obs_data_get_string(preset, "value")
                --log("check %s", preset_value)
                
                local preset_name, preset_id = parse_preset_value(preset_value)
                if (preset_name ~= nil) and (preset_id ~= nil) then
                    obs.obs_property_list_add_int(prop_presets, preset_name, preset_id)
                    if first_preset then
                        obs.obs_data_set_default_int(plugin_settings, "scene_" .. cam_prop_prefix .. "preset", preset_id)
                        first_preset = false
                    end
                end
            end
        end
        
        obs.obs_data_array_release(presets)
    end

	local prop_active = obs.obs_properties_add_list(props, "scene_active", "Action Active:", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	obs.obs_property_list_add_int(prop_active, "On Program", action_active.Program)
	obs.obs_property_list_add_int(prop_active, "On Preview", action_active.Preview)
	obs.obs_property_list_add_int(prop_active, "Always", action_active.Always)

	obs.obs_properties_add_bool(props, "preview_exclusive", "Run action on preview only when the camera is not active on program")

    --obs.obs_properties_add_button(props, "run_action", "Perform action now", cb_run_action)

    obs.obs_property_set_modified_callback(prop_camera, cb_camera_changed)

	return props
end

local function do_cam_scene_action(settings, source_name)
    local camera_id = obs.obs_data_get_int(settings, "scene_camera")
    local scene_action = obs.obs_data_get_int(settings, "scene_action")
    local scene_animation_direction = obs.obs_data_get_int(settings, "scene_animation_direction")
    local scene_animation_speed = obs.obs_data_get_double(settings, "scene_animation_speed")
    local cam_prop_prefix = string.format("cam_%d_", camera_id)
    local preset_id = obs.obs_data_get_int(settings, "scene_".. cam_prop_prefix .. "preset")

    do_cam_action_start(camera_id, scene_action, preset_id, scene_animation_direction, scene_animation_speed)
    table.insert(previous_actions, {camera_id=camera_id, scene_action=scene_action, source_name=source_name})
end

function cb_camera_changed(props, property, data)
    local changed = false
    local num_cameras = obs.obs_property_list_item_count(property)
    local cam_idx = obs.obs_data_get_int(data, obs.obs_property_name(property))
    if cnt == 0 then
        cam_idx = 0
    end
    
    for camera_id = 1, num_cameras do
        local visible = cam_idx == camera_id
        log("cb_camera_changed %d %d %d", camera_id, cam_idx, visible and 1 or 0)
        
        local cam_prop_prefix = string.format("scene_cam_%d_", camera_id)

        local cam_props = {"preset"}
        for _,cam_prop_name in pairs(cam_props) do
            local cam_prop = obs.obs_properties_get(props, cam_prop_prefix .. cam_prop_name)
            if cam_prop then
                if obs.obs_property_visible(cam_prop) ~= visible then
                    obs.obs_property_set_visible(cam_prop, visible)
                    changed = true
                end
            end
        end
    end
    
    return changed
end

local function camera_active_on_program(preview_camera_id)
    local active = false

    local program_source = obs.obs_frontend_get_current_scene()
    if program_source ~= nil then
        local program_scene = obs.obs_scene_from_source(program_source)
        local program_scene_name = obs.obs_source_get_name(program_source)
        log("Current program scene is %s", program_scene_name or "?")

        local program_scene_items = obs.obs_scene_enum_items(program_scene)
        if program_scene_items ~= nil then
            for _, program_scene_item in ipairs(program_scene_items) do
                local program_scene_item_source = obs.obs_sceneitem_get_source(program_scene_item)
                local program_scene_item_source_id = obs.obs_source_get_unversioned_id(program_scene_item_source)
                if program_scene_item_source_id == plugin_def.id then
                    local visible = obs.obs_source_showing(program_scene_item_source)
                    if visible then
                        local program_item_source_settings = obs.obs_source_get_settings(program_scene_item_source)
                        if program_item_source_settings ~= nil then
                            local program_camera_id = obs.obs_data_get_int(program_item_source_settings, "scene_camera")
                            log("Camera active on preview: %d active on program: %d", preview_camera_id, program_camera_id)
                            if preview_camera_id == program_camera_id then
                                active = true
                                break
                            end

                            obs.obs_data_release(program_item_source_settings)
                        end
                    end
                end
            end

            obs.sceneitem_list_release(program_scene_items)
        end

        obs.obs_source_release(program_source)
    end

    return active
end

function fe_callback(event, data)
    if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
        --local scenesource = obs.obs_frontend_get_current_scene()
        -- log("fe_callback OBS_FRONTEND_EVENT_SCENE_CHANGED to %s", plugin_data.active_scene or "?")
        --obs.obs_source_release(scenesource)
    elseif event == obs.OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED then
        local scenesource = obs.obs_frontend_get_current_preview_scene()
        if scenesource ~= nil then
            local scene = obs.obs_scene_from_source(scenesource)
            local scene_name = obs.obs_source_get_name(scenesource)
            if plugin_data.preview_scene ~= scene_name then
                plugin_data.preview_scene = scene_name
                log("OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED to %s", scene_name or "?")

                for a,data in pairs(previous_actions) do
                    log("preview camera stop")
                    do_cam_action_stop(data.camera_id, data.scene_action)
                end
                previous_actions = {}

                local scene_items = obs.obs_scene_enum_items(scene)
                if scene_items ~= nil then
                    for _, scene_item in ipairs(scene_items) do
                        local source = obs.obs_sceneitem_get_source(scene_item)
                        local source_id = obs.obs_source_get_unversioned_id(source)
                        if source_id == plugin_def.id then
                            local settings = obs.obs_source_get_settings(source)
                            local source_name = obs.obs_source_get_name(source)
                            local visible = obs.obs_source_showing(source)

                            if visible then
                                local do_action = false
                                local active = obs.obs_data_get_int(settings, "scene_active")

                                if (active == action_active.Preview) or (active == action_active.Always) then
                                    do_action = true

                                    local preview_exclusive = obs.obs_data_get_bool(settings, "preview_exclusive")
                                    if preview_exclusive then
                                        local preview_camera_id = obs.obs_data_get_int(settings, "scene_camera")
                                        if camera_active_on_program(preview_camera_id) then
                                            do_action = false
                                        end
                                    end
                                end

                                if do_action then
                                    log("Running Visca for source '%s'", source_name or "?")
                                    do_cam_scene_action(settings, source_name)
                                end
                            end

                            obs.obs_data_release(settings)
                        end
                    end
                end

                obs.sceneitem_list_release(scene_items)
            end

            obs.obs_source_release(scenesource)
        end
    end
end

function signal_on_activate(calldata)
    local source = obs.calldata_source(calldata, "source")
	local settings = obs.obs_source_get_settings(source)
	local source_name = obs.obs_source_get_name(source)

    local do_action = false
    local active = obs.obs_data_get_int(settings, "scene_active")
    if (active == action_active.Program) or (active == action_active.Always) then
        do_action = true
    end

    if do_action then
        do_cam_scene_action(settings, source_name)
    end

	obs.obs_data_release(settings)
end

function signal_on_deactivate(calldata)
    local source = obs.calldata_source(calldata, "source")
	local source_name = obs.obs_source_get_name(source)
    for a, data in pairs(previous_actions) do
        -- log("pair %d action %s %s", a, data.source_name or 0, source_name)
        if data.source_name == source_name and data.scene_action == actions.Animate then
            if previous_actions[a+1] == nil then  -- only stop if there is no newer action
                log("Camera stopping action of %s with action type %d", source_name, data.scene_action or 0)
                do_cam_action_stop(data.camera_id, data.scene_action)
                -- table.remove(previous_actions, a)
            else
                log("Newest action exists (is %s) not stopping camera action", previous_actions[a+1].source_name)
            end
            previous_actions = {}
        end
    end
end

obs.obs_register_source(plugin_def)
