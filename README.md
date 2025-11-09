# Mining Telemetry

A Factorio 2.0 mod that adds new circuit network signals to mining drills and resource extractors (like pumpjacks), enabling advanced circuit network logic and monitoring.

## Features

### Entity Counter Signal
Outputs a signal with the mining drill's icon and a value of 1. This is useful for counting how many miners are connected to a circuit network at a mining outpost.

### No Resources Signal
Outputs a configurable signal (defaults to "N") when a mining drill has no resources left to extract. This allows you to:
- Detect depleted mining patches
- Trigger automatic miner removal or repositioning
- Monitor resource depletion across your factory

### Configuration Options

- **Per-Entity Settings**: Each mining drill can be configured individually through its GUI
- **Global Default**: Set a default "no resources" signal in mod settings that applies to all new miners
- **Signal Override**: Override the "no resources" signal per-entity for special cases
- **Toggle Signals**: Both signals can be enabled/disabled independently and default to off

## How to Use

1. Place a mining drill and connect it to a circuit network
2. Open the mining drill's GUI
3. In the "Mining Telemetry" panel, check the boxes for the signals you want to enable:
   - **Entity counter**: Always outputs 1 (using the drill's icon as the signal)
   - **No resources signal**: Outputs 1 when the drill has no resources (customizable signal)
4. Optionally, click the signal selector to customize which signal is used for "no resources"

## Technical Details

- Signals update every 60 ticks (once per second)
- Uses hidden constant combinators to output custom signals
- Automatically syncs wire connections when you connect/disconnect circuit wires
- Zero performance impact when signals are disabled
- Compatible with all mining drill types

## Requirements

- Factorio 2.0 or higher

## Installation

1. Download the latest release
2. Extract to your Factorio mods folder
3. Enable the mod in-game

## Source Code

Available on [GitHub](https://github.com/utoxin/mining-telemetry)

## License

This mod is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Author

Utoxin

## Version History

See [changelog.txt](mining-telemetry/changelog.txt) for detailed version history.
