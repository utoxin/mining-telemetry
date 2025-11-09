-- Mining Telemetry - Settings
-- Global mod settings

data:extend({
    {
        type = "string-setting",
        name = "mining-telemetry-default-no-resources-signal",
        setting_type = "runtime-global",
        default_value = "signal-N",
        order = "a"
    },
    {
        type = "bool-setting",
        name = "mining-telemetry-disable-entity-counter-when-depleted",
        setting_type = "runtime-global",
        default_value = false,
        order = "b"
    }
})
