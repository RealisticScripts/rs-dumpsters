# rs-dumpsters

Realistic dumpster script for FiveM.

## Features

- Loot dumpsters
- Stash items in dumpsters
- Hide in dumpsters
- ox_lib notifications
- Supports `ox_target` and `qb-target`
- Supports `ox_inventory` and `qb-inventory`
- Persistent dumpster stashes across server restarts (with shipped SQL + auto table creation)
- Debug logging and in-world debug marker/text when `Config.Debug = true`
- Discord logging

## Requirements

- `ox_lib`
- One supported target resource:
  - `ox_target`
  - `qb-target`
- One supported inventory resource:
  - `ox_inventory`
  - `qb-inventory`
- A working MySQL layer for your inventory backend (the resource auto-creates its `rs_dumpsters_stashes` table when available)
- `oxmysql` for the built-in auto SQL path

## Installation

1. Place `rs-dumpsters` in your resources folder.
2. Ensure the required dependencies are started before this resource.
3. Add `ensure rs-dumpsters` to your server config.
4. Restart the server.
5. The resource will auto-create the `rs_dumpsters_stashes` table on first start when MySQL is available.

## Database / SQL

The package now includes `sql/rs_dumpsters.sql`.

You have two valid ways to get the table in place:

1. **Auto SQL**: start the resource with `oxmysql` running and the included `@oxmysql/lib/MySQL.lua` bootstrap will create `rs_dumpsters_stashes` automatically with `CREATE TABLE IF NOT EXISTS`.
2. **Manual import**: import `sql/rs_dumpsters.sql` yourself before starting the resource.

The auto-create path and the shipped SQL file use the same schema.

## Configuration

All configuration is in `config.lua`.

### Target selection

Choose the target system in `config.lua`:

```lua
Config.TargetSystem = 'qb-target' -- 'qb-target' or 'ox_target'
```

The resource will only register the target system you select. It will not silently switch to the other one.

### Inventory item names

The loot table uses item names exactly as they exist in your inventory.

Default entries are:

- `plastic`
- `metalscrap`
- `glass`
- `lockpick`
- `phone`
- `radio`

If your server uses different item names, update `Config.LootTable` to match your registered items.

## Behavior

### Loot dumpsters

- Each dumpster is identified by model + rounded world coordinates.
- Successful and empty searches apply a cooldown to that dumpster.
- If the player cannot carry the reward, the cooldown is not consumed.

### Stash items in dumpsters

- Each dumpster has its own persistent stash inventory.
- Dumpster stash identities are recorded in the database and restored on restart.
- Item persistence still relies on the selected inventory backend's own database storage, which both supported inventories already use for stash/inventory data.

### Hide in dumpsters

- One player can occupy a dumpster at a time.
- Press `E` to exit the dumpster.
- While hidden, the camera is forced to a fixed exterior street-side view looking at the dumpster instead of relying on gameplay camera position. The view is pulled farther back and slightly widened so you can better see people moving past the dumpster.
- Exiting now prefers the same outside/front side of the dumpster, then falls back to the left/right sides, with a rear-side fallback only if every better spot is blocked.
- Hide state is safely cleaned up on disconnect and resource stop.

## Debug

When `Config.Debug = true`:

- server and client print structured debug output
- the client draws a debug marker and text over the nearest dumpster within range

## Discord logging

The script logs these actions to the configured webhook:

- successful loot
- empty loot result
- stash opened
- player hid in dumpster

## Notes

- Targeting is explicitly selected with `Config.TargetSystem`.
- The script auto-detects the active supported inventory backend.
- Valid target values are `qb-target`, `qb_target`, `ox_target`, and `ox-target`.
- `ox_inventory` is preferred when both supported inventory resources are running.
- On startup the resource creates and uses an `rs_dumpsters_stashes` table through `oxmysql`, so known dumpster stash ids are restored automatically.
- The package also ships `sql/rs_dumpsters.sql` for manual import if you prefer explicit DB setup.

## Suggested future additions

Not included in this release, but clean fits if you want to expand later:

- police chance / evidence chance when dumpster diving
- job-locked dumpster models or zones
- per-model loot tables

## License

MIT License © 2026 Realistic Scripts