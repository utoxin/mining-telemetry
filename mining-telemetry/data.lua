-- Mining Telemetry - Data Stage

-- Create a hidden constant combinator that can't be selected or interacted with
local hidden_combinator = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
hidden_combinator.name = "mining-telemetry-hidden-combinator"
hidden_combinator.selectable_in_game = false
hidden_combinator.selection_box = nil
hidden_combinator.collision_box = {{0, 0}, {0, 0}}
hidden_combinator.collision_mask = {layers={}}

data:extend({hidden_combinator})
