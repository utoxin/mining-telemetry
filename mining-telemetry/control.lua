-- Mining Telemetry - Control Script
-- Adds circuit network signals to mining drills and pumpjacks

-- Data structure for entity configuration:
-- storage.entity_config[unit_number] = {
--   entity = LuaEntity reference,
--   combinator = LuaEntity reference (hidden constant combinator),
--   enable_entity_counter = bool (default: false),
--   enable_no_resources = bool (default: false),
--   no_resources_signal = SignalID (falls back to global setting)
-- }

-- Initialize storage data on mod initialization
script.on_init(function()
    storage.entity_config = {}
    storage.player_open_entity = {}
end)

-- Handle configuration changes (mod updates)
script.on_configuration_changed(function(data)
    storage.entity_config = storage.entity_config or {}
    storage.player_open_entity = storage.player_open_entity or {}
    -- Clean up invalid entities and their combinators
    for unit_number, config in pairs(storage.entity_config) do
        if not config.entity or not config.entity.valid then
            destroy_combinator(config)
            storage.entity_config[unit_number] = nil
        end
    end
end)

-- Helper function to check if entity type is supported
local function is_supported_entity(entity)
    return entity and entity.valid and entity.type == "mining-drill"
end

-- Helper function to get default no-resources signal
local function get_default_no_resources_signal()
    local signal_name = settings.global["mining-telemetry-default-no-resources-signal"].value
    return {type = "virtual", name = signal_name}
end

-- Helper function to check if a mining drill has resources
local function has_resources(entity)
    if not entity or not entity.valid then return false end

    -- Check if the entity is a mining drill
    if entity.type ~= "mining-drill" then return false end

    -- Get mining target (the resource entity being mined)
    local mining_target = entity.mining_target
    if not mining_target then return false end

    -- Check if the mining target has any resources left
    if mining_target.amount and mining_target.amount > 0 then
        return true
    end

    return false
end

-- Create a hidden constant combinator for a mining drill
local function create_combinator(entity)
    if not entity or not entity.valid then return nil end

    -- Create hidden constant combinator at the same position
    local combinator = entity.surface.create_entity{
        name = "mining-telemetry-hidden-combinator",
        position = entity.position,
        force = entity.force,
        create_build_effect_smoke = false
    }

    if not combinator then return nil end

    -- Make the combinator hidden and indestructible
    combinator.minable = false
    combinator.destructible = false
    combinator.operable = false  -- Players can't open it
    combinator.rotatable = false

    -- Connect the combinator directly to the drill (simpler and cleaner visually)
    for _, wire_connector_id in pairs({defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green}) do
        local drill_connector = entity.get_wire_connector(wire_connector_id, false)
        local combinator_connector = combinator.get_wire_connector(wire_connector_id, false)

        if drill_connector and combinator_connector then
            -- Check if the drill has any connections on this wire color
            if #drill_connector.connections > 0 then
                -- Connect the combinator to the drill
                combinator_connector.connect_to(drill_connector, false)
            end
        end
    end

    return combinator
end

-- Destroy the constant combinator for a mining drill
local function destroy_combinator(config)
    if config and config.combinator and config.combinator.valid then
        config.combinator.destroy()
        config.combinator = nil
    end
end

-- Sync the combinator's wire connections to match the drill
local function sync_combinator_wires(entity, combinator)
    if not entity or not entity.valid or not combinator or not combinator.valid then return end

    -- Check each wire color
    for _, wire_connector_id in pairs({defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green}) do
        local drill_connector = entity.get_wire_connector(wire_connector_id, false)
        local combinator_connector = combinator.get_wire_connector(wire_connector_id, false)

        if drill_connector and combinator_connector then
            local drill_has_connections = #drill_connector.connections > 0
            local combinator_connected_to_drill = false

            -- Check if combinator is already connected to drill
            for _, wire_connection in pairs(combinator_connector.connections) do
                if wire_connection.target == drill_connector then
                    combinator_connected_to_drill = true
                    break
                end
            end

            -- Update connection state to match
            if drill_has_connections and not combinator_connected_to_drill then
                -- Drill has connections but combinator isn't connected - connect it
                combinator_connector.connect_to(drill_connector, false)
            elseif not drill_has_connections and combinator_connected_to_drill then
                -- Drill has no connections but combinator is connected - disconnect it
                combinator_connector.disconnect_from(drill_connector)
            end
        end
    end
end

-- Get or create entity configuration
local function get_entity_config(entity)
    if not entity or not entity.valid then return nil end

    local unit_number = entity.unit_number
    if not storage.entity_config[unit_number] then
        storage.entity_config[unit_number] = {
            entity = entity,
            combinator = nil,  -- Created on demand when signals are enabled
            enable_entity_counter = false,
            enable_no_resources = false,
            no_resources_signal = nil  -- nil means use global default
        }
    end

    return storage.entity_config[unit_number]
end

-- Update circuit signals for an entity
local function update_entity_signals(entity)
    if not is_supported_entity(entity) then return end

    local config = get_entity_config(entity)
    if not config then return end

    -- Check if any signals are enabled
    local signals_enabled = config.enable_entity_counter or config.enable_no_resources

    -- If no signals enabled, destroy combinator and return
    if not signals_enabled then
        destroy_combinator(config)
        return
    end

    -- Create combinator if needed
    if not config.combinator or not config.combinator.valid then
        config.combinator = create_combinator(entity)
        if not config.combinator then return end
    end

    -- Build signals table
    local signals = {}
    local signal_index = 1

    -- Signal #1: Entity counter (outputs entity's own icon with value 1)
    if config.enable_entity_counter then
        signals[signal_index] = {
            signal = {type = "item", name = entity.name},
            count = 1,
            index = signal_index
        }
        signal_index = signal_index + 1
    end

    -- Signal #2: No resources indicator
    if config.enable_no_resources then
        local no_resources = not has_resources(entity)
        if no_resources then
            local signal = config.no_resources_signal or get_default_no_resources_signal()
            signals[signal_index] = {
                signal = signal,
                count = 1,
                index = signal_index
            }
            signal_index = signal_index + 1
        end
    end

    -- Set the signals on the constant combinator
    local control = config.combinator.get_or_create_control_behavior()
    if control then
        -- Ensure we have at least one section
        if control.sections_count == 0 then
            control.add_section()
        end

        local section = control.get_section(1)
        if section then
            -- Clear all existing slots first
            for i = 1, section.filters_count do
                section.clear_slot(i)
            end

            -- Set new signals
            for i, signal_data in ipairs(signals) do
                section.set_slot(i, {
                    value = {
                        type = signal_data.signal.type,
                        name = signal_data.signal.name,
                        quality = "normal"
                    },
                    min = signal_data.count
                })
            end
        end
    end
end

-- Register entities when they are built
local function on_entity_created(event)
    local entity = event.entity or event.created_entity or event.destination
    if not is_supported_entity(entity) then return end

    -- Initialize configuration for this entity
    get_entity_config(entity)
end

-- Clean up when entities are removed
local function on_entity_removed(event)
    local entity = event.entity
    if not entity or not entity.valid then return end

    if entity.type == "mining-drill" then
        local unit_number = entity.unit_number
        local config = storage.entity_config[unit_number]
        if config then
            destroy_combinator(config)
            storage.entity_config[unit_number] = nil
        end
    end
end

-- Periodic update to refresh circuit signals
local function on_tick(event)
    -- Update all monitored entities
    for unit_number, config in pairs(storage.entity_config) do
        if config.entity and config.entity.valid then
            -- Only update if at least one signal is enabled
            if config.enable_entity_counter or config.enable_no_resources then
                update_entity_signals(config.entity)

                -- Sync wire connections if combinator exists
                if config.combinator and config.combinator.valid then
                    sync_combinator_wires(config.entity, config.combinator)
                end
            end
        else
            -- Clean up invalid entities and their combinators
            destroy_combinator(config)
            storage.entity_config[unit_number] = nil
        end
    end
end

-- Register event handlers
script.on_event(defines.events.on_built_entity, on_entity_created)
script.on_event(defines.events.on_robot_built_entity, on_entity_created)
script.on_event(defines.events.script_raised_built, on_entity_created)
script.on_event(defines.events.script_raised_revive, on_entity_created)

script.on_event(defines.events.on_entity_died, on_entity_removed)
script.on_event(defines.events.on_player_mined_entity, on_entity_removed)
script.on_event(defines.events.on_robot_mined_entity, on_entity_removed)
script.on_event(defines.events.script_raised_destroy, on_entity_removed)

-- Update signals every 60 ticks (once per second)
script.on_nth_tick(60, on_tick)

-- ============================================================================
-- GUI System
-- ============================================================================

-- GUI element names
local GUI_NAMES = {
    main_frame = "mining-telemetry-config-frame",
    entity_counter_checkbox = "mining-telemetry-entity-counter-checkbox",
    no_resources_checkbox = "mining-telemetry-no-resources-checkbox",
    no_resources_signal_button = "mining-telemetry-no-resources-signal-button"
}

-- Store which entity each player is currently configuring
-- storage.player_open_entity[player_index] = unit_number

-- Create the configuration GUI for a mining drill
local function create_config_gui(player, entity)
    if not is_supported_entity(entity) then return end

    -- Close any existing GUI first
    destroy_config_gui(player)

    local config = get_entity_config(entity)
    if not config then return end

    -- Store which entity this player is configuring
    storage.player_open_entity[player.index] = entity.unit_number

    -- Create the main frame anchored to the entity GUI
    local frame = player.gui.relative.add{
        type = "frame",
        name = GUI_NAMES.main_frame,
        direction = "vertical",
        anchor = {
            gui = defines.relative_gui_type.mining_drill_gui,
            position = defines.relative_gui_position.right
        }
    }

    -- Title
    frame.add{
        type = "label",
        caption = {"mining-telemetry.gui-title"},
        style = "frame_title"
    }

    -- Entity counter checkbox
    local entity_counter_flow = frame.add{type = "flow", direction = "horizontal"}
    entity_counter_flow.add{
        type = "checkbox",
        name = GUI_NAMES.entity_counter_checkbox,
        caption = {"mining-telemetry.entity-counter-label"},
        state = config.enable_entity_counter,
        tooltip = {"mining-telemetry.entity-counter-tooltip"}
    }

    -- No resources checkbox
    local no_resources_flow = frame.add{type = "flow", direction = "horizontal"}
    no_resources_flow.add{
        type = "checkbox",
        name = GUI_NAMES.no_resources_checkbox,
        caption = {"mining-telemetry.no-resources-label"},
        state = config.enable_no_resources,
        tooltip = {"mining-telemetry.no-resources-tooltip"}
    }

    -- Signal selector for "no resources"
    local signal = config.no_resources_signal or get_default_no_resources_signal()
    frame.add{
        type = "choose-elem-button",
        name = GUI_NAMES.no_resources_signal_button,
        elem_type = "signal",
        signal = signal,
        tooltip = {"mining-telemetry.no-resources-signal-tooltip"},
        enabled = config.enable_no_resources
    }
end

-- Destroy the configuration GUI for a player
function destroy_config_gui(player)
    local frame = player.gui.relative[GUI_NAMES.main_frame]
    if frame then
        frame.destroy()
    end
    storage.player_open_entity[player.index] = nil
end

-- Handle GUI opened event
local function on_gui_opened(event)
    if event.entity and is_supported_entity(event.entity) then
        local player = game.get_player(event.player_index)
        if player then
            create_config_gui(player, event.entity)
        end
    end
end

-- Handle GUI closed event
local function on_gui_closed(event)
    if event.entity and is_supported_entity(event.entity) then
        local player = game.get_player(event.player_index)
        if player then
            destroy_config_gui(player)
        end
    end
end

-- Handle checkbox state changes
local function on_gui_checked_state_changed(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    local unit_number = storage.player_open_entity[player.index]
    if not unit_number then return end

    local config = storage.entity_config[unit_number]
    if not config or not config.entity or not config.entity.valid then return end

    local element = event.element
    if element.name == GUI_NAMES.entity_counter_checkbox then
        config.enable_entity_counter = element.state
        update_entity_signals(config.entity)
    elseif element.name == GUI_NAMES.no_resources_checkbox then
        config.enable_no_resources = element.state
        update_entity_signals(config.entity)

        -- Enable/disable the signal picker based on checkbox state
        local frame = player.gui.relative[GUI_NAMES.main_frame]
        if frame then
            local signal_button = frame[GUI_NAMES.no_resources_signal_button]
            if signal_button then
                signal_button.enabled = element.state
            end
        end
    end
end

-- Handle signal selection changes
local function on_gui_elem_changed(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    local unit_number = storage.player_open_entity[player.index]
    if not unit_number then return end

    local config = storage.entity_config[unit_number]
    if not config or not config.entity or not config.entity.valid then return end

    local element = event.element
    if element.name == GUI_NAMES.no_resources_signal_button then
        config.no_resources_signal = element.elem_value
        update_entity_signals(config.entity)
    end
end

-- Register GUI event handlers
script.on_event(defines.events.on_gui_opened, on_gui_opened)
script.on_event(defines.events.on_gui_closed, on_gui_closed)
script.on_event(defines.events.on_gui_checked_state_changed, on_gui_checked_state_changed)
script.on_event(defines.events.on_gui_elem_changed, on_gui_elem_changed)
