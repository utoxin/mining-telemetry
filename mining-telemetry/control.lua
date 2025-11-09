-- Mining Telemetry - Control Script
-- Adds circuit network signals to mining drills and pumpjacks

-- Data structure for entity configuration:
-- storage.entity_config[unit_number] = {
--   entity = LuaEntity reference,
--   combinator = LuaEntity reference (hidden constant combinator),
--   enable_entity_counter = bool (default: false),
--   enable_no_resources = bool (default: false),
--   no_resources_signal = SignalID (falls back to global setting),
--   enable_effective_resources = bool (default: false)
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
    -- Clean up invalid entities and their combinators, and migrate old configs
    for unit_number, config in pairs(storage.entity_config) do
        if not config.entity or not config.entity.valid then
            destroy_combinator(config)
            storage.entity_config[unit_number] = nil
        else
            -- Migrate old configs that don't have the new field
            if config.enable_effective_resources == nil then
                config.enable_effective_resources = false
            end
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

    -- Get or create control behavior
    local control = entity.get_or_create_control_behavior()
    if not control then return false end

    -- Temporarily enable resource reading for just the mining area
    local original_read_state = control.circuit_read_resources
    local original_read_mode = control.resource_read_mode

    control.circuit_read_resources = true
    control.resource_read_mode = defines.control_behavior.mining_drill.resource_read_mode.this_miner

    -- Get the resource targets in the mining area
    local targets = control.resource_read_targets

    -- Restore original settings
    control.circuit_read_resources = original_read_state
    control.resource_read_mode = original_read_mode

    if not targets or #targets == 0 then return false end

    -- Return early as soon as we find any resource with amount > 0
    for _, resource in pairs(targets) do
        if resource.valid and resource.amount and resource.amount > 0 then
            return true
        end
    end

    return false
end

-- Get total resources in the patch using drill's resource reading
local function get_patch_resources(entity)
    if not entity or not entity.valid or entity.type ~= "mining-drill" then return 0 end

    -- Get or create control behavior
    local control = entity.get_or_create_control_behavior()
    if not control then return 0 end

    -- Temporarily enable resource reading to get the targets
    local original_read_state = control.circuit_read_resources
    local original_read_mode = control.resource_read_mode

    -- Set to read entire field
    control.circuit_read_resources = true
    control.resource_read_mode = defines.control_behavior.mining_drill.resource_read_mode.entire_patch

    -- Get the resource targets (all resources in the patch)
    local targets = control.resource_read_targets

    -- Restore original settings
    control.circuit_read_resources = original_read_state
    control.resource_read_mode = original_read_mode

    if not targets or #targets == 0 then return 0 end

    -- Sum up all resources in the patch
    local total = 0
    for _, resource in pairs(targets) do
        if resource.valid and resource.amount then
            total = total + resource.amount
        end
    end

    return total
end

-- Calculate effective resources accounting for productivity and drain modifiers
local function calculate_effective_resources(entity)
    if not entity or not entity.valid or entity.type ~= "mining-drill" then return 0 end

    -- Get the base resource count for the entire patch
    local base_resources = get_patch_resources(entity)
    if base_resources == 0 then return 0 end

    -- Apply mining productivity bonus
    local productivity_bonus = entity.force.mining_drill_productivity_bonus or 0
    local productivity_multiplier = 1 + productivity_bonus

    -- Apply resource drain modifier (big mining drills have reduced drain)
    local resource_drain_modifier = 1
    local prototype = entity.prototype
    if prototype and prototype.resource_drain_rate_percent then
        resource_drain_modifier = prototype.resource_drain_rate_percent / 100
    end

    -- Calculate effective resources
    local effective_resources = base_resources * productivity_multiplier / resource_drain_modifier

    return math.floor(effective_resources)
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
            no_resources_signal = nil,  -- nil means use global default
            enable_effective_resources = false
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
    local signals_enabled = config.enable_entity_counter or config.enable_no_resources or config.enable_effective_resources

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

    -- Check if entity has resources (used by multiple signals)
    local entity_has_resources = has_resources(entity)
    local disable_counter_when_depleted = false
    local setting = settings.global["mining-telemetry-disable-entity-counter-when-depleted"]
    if setting then
        disable_counter_when_depleted = setting.value
    end

    -- Signal #1: Entity counter (outputs entity's own icon with value 1)
    if config.enable_entity_counter then
        -- Only output if resources exist OR the global setting allows it
        if entity_has_resources or not disable_counter_when_depleted then
            signals[signal_index] = {
                signal = {type = "item", name = entity.name},
                count = 1,
                index = signal_index
            }
            signal_index = signal_index + 1
        end
    end

    -- Signal #2: No resources indicator
    if config.enable_no_resources then
        if not entity_has_resources then
            local signal = config.no_resources_signal or get_default_no_resources_signal()
            signals[signal_index] = {
                signal = signal,
                count = 1,
                index = signal_index
            }
            signal_index = signal_index + 1
        end
    end

    -- Signal #3: Effective resources (total patch resources with modifiers)
    if config.enable_effective_resources then
        local effective_resources = calculate_effective_resources(entity)
        if effective_resources > 0 then
            -- Get the resource type from mining target
            local mining_target = entity.mining_target
            if mining_target and mining_target.valid then
                signals[signal_index] = {
                    signal = {type = "item", name = mining_target.name},
                    count = effective_resources,
                    index = signal_index
                }
                signal_index = signal_index + 1
            end
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

    -- Restore settings from blueprint tags if available
    if event.tags and event.tags["mining-telemetry"] then
        local config = get_entity_config(entity)
        if config then
            local tags = event.tags["mining-telemetry"]
            config.enable_entity_counter = tags.enable_entity_counter or false
            config.enable_no_resources = tags.enable_no_resources or false
            config.no_resources_signal = tags.no_resources_signal
            config.enable_effective_resources = tags.enable_effective_resources or false
            -- Update signals immediately if any are enabled
            if config.enable_entity_counter or config.enable_no_resources or config.enable_effective_resources then
                update_entity_signals(entity)
            end
        end
    end
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
            if config.enable_entity_counter or config.enable_no_resources or config.enable_effective_resources then
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

-- Handle copy/paste of entity settings
local function on_entity_settings_pasted(event)
    local source = event.source
    local destination = event.destination

    if not is_supported_entity(source) or not is_supported_entity(destination) then return end

    local source_config = storage.entity_config[source.unit_number]
    if not source_config then return end

    -- Copy settings to destination
    local dest_config = get_entity_config(destination)
    if dest_config then
        dest_config.enable_entity_counter = source_config.enable_entity_counter
        dest_config.enable_no_resources = source_config.enable_no_resources
        dest_config.no_resources_signal = source_config.no_resources_signal
        dest_config.enable_effective_resources = source_config.enable_effective_resources

        -- Update signals immediately if any are enabled
        if dest_config.enable_entity_counter or dest_config.enable_no_resources or dest_config.enable_effective_resources then
            update_entity_signals(destination)
        end
    end
end

-- Handle blueprint creation - store settings as tags
local function on_player_setup_blueprint(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    local blueprint = player.blueprint_to_setup
    if not blueprint or not blueprint.valid_for_read then
        blueprint = player.cursor_stack
    end

    if not blueprint or not blueprint.valid_for_read or not blueprint.is_blueprint then return end

    local entities = blueprint.get_blueprint_entities()
    if not entities then return end

    -- Store settings for each mining drill in the blueprint
    for i, bp_entity in pairs(entities) do
        local surface_entities = player.surface.find_entities_filtered{
            position = bp_entity.position,
            type = "mining-drill",
            limit = 1
        }

        if surface_entities[1] then
            local entity = surface_entities[1]
            local config = storage.entity_config[entity.unit_number]

            if config and (config.enable_entity_counter or config.enable_no_resources or config.enable_effective_resources) then
                blueprint.set_blueprint_entity_tag(i, "mining-telemetry", {
                    enable_entity_counter = config.enable_entity_counter,
                    enable_no_resources = config.enable_no_resources,
                    no_resources_signal = config.no_resources_signal,
                    enable_effective_resources = config.enable_effective_resources
                })
            end
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

-- Handle copy/paste and blueprint operations
script.on_event(defines.events.on_entity_settings_pasted, on_entity_settings_pasted)
script.on_event(defines.events.on_player_setup_blueprint, on_player_setup_blueprint)

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
    no_resources_signal_button = "mining-telemetry-no-resources-signal-button",
    effective_resources_checkbox = "mining-telemetry-effective-resources-checkbox"
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

    -- Effective resources checkbox
    local effective_resources_flow = frame.add{type = "flow", direction = "horizontal"}
    effective_resources_flow.add{
        type = "checkbox",
        name = GUI_NAMES.effective_resources_checkbox,
        caption = {"mining-telemetry.effective-resources-label"},
        state = config.enable_effective_resources or false,
        tooltip = {"mining-telemetry.effective-resources-tooltip"}
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
    elseif element.name == GUI_NAMES.effective_resources_checkbox then
        config.enable_effective_resources = element.state
        update_entity_signals(config.entity)
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
