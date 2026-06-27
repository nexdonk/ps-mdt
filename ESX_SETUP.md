# ps-mdt — ESX (es_extended) setup

ps-mdt now runs on **ESX Legacy (1.9+)** in addition to QBCore/Qbox. The
framework is auto-detected by `ps_lib`, so the same files work on all three.
Follow these ESX-specific steps.

## 1. Database

Import **`sql/esx.sql`** (NOT `qbcore.sql` / `qbx.sql`).

It creates all `mdt_*` tables and an **ESX compatibility layer**:

- Ensures `users` has `metadata` (LONGTEXT) and `phone_number` columns.
- Ensures `owned_vehicles` has a surrogate `id`, the MDT vehicle columns and an
  `mdt_impound_state` flag.
- Creates two **views** that mirror the QBCore schema the MDT queries directly:
  - `players`  → built over `users`
  - `player_vehicles` → built over `owned_vehicles`

Requirements: **MariaDB** (the script uses `ADD COLUMN IF NOT EXISTS`) and a
schema where `users`, `owned_vehicles`, `jobs` and `job_grades` exist (standard
ESX Legacy). Back up your database before importing.

## 2. Resource order

Start `ps_lib` and `oxmysql`/`ox_lib` before `ps-mdt`, after `es_extended`.
`ps_lib` auto-detects ESX via `es_extended`.

## 3. Configuration

`ps-mdt/config.lua` auto-detects ESX (`IsESX`) and switches a few defaults.
Review and set for your server:

- **Job access** — list your ESX LEO/EMS/DOJ job *names* in
  `Config.PoliceJobs`, `Config.MedicalJobs`, `Config.DojJobs`. MDT access is
  granted by job name on ESX.
- **Job types** — map ESX job names → type (`leo`/`ems`/`doj`) in
  `ps_lib/Config.lua` → `Config.ESXJobTypes` (used by the `players` view's job
  `type` and the bridge's `getJobType`). The view's CASE list and this config
  ship with common names already.
- **Jail** (`Config.Jail`) — the MDT writes `injail`/`criminalrecord` metadata
  and triggers a jail script. ESX has no built-in jail, so wire yours:
  - `ServerEvent` → e.g. your jail server event `TriggerEvent(ServerEvent, src, time)`.
  - `ClientEvent`  → a client event on the target (default empty on ESX).
  - `TimeMultiplier` → convert MDT "months" to your jail's unit.
- **Bodycams** (`Config.Bodycam`) — defaults to `pslib` mode on ESX. ESX has no
  native server-side duty event, so to auto-create bodycams on duty change call
  `TriggerEvent('ps_lib:server:dutyChanged', src, jobName, onDuty)` from your
  duty system. Bodycam *viewing* works without this.

## 4. Known ESX limitations / notes

- **Vehicle model names**: the `player_vehicles` view exposes
  `owned_vehicles.vehicle->'$.model'`. If your server stores the model as a hash
  (default ESX), the MDT shows that value; if it stores a spawn name it resolves
  cleanly. This is display-only and never errors.
- **Impound**: marking/releasing impound uses the MDT's own `mdt_impound_state`
  flag and (on release) respawns the vehicle by model at the impound lot. Deep
  garage integration (blocking retrieval) is server/garage-specific.
- **Offline players**: name lookups for offline citizens read from `users`; some
  online-only actions (radio, GPS, jail) still require the player to be online,
  same as QBCore.
- **Callsign**: stored in `mdt_profiles` and mirrored to ESX player metadata
  (`setMeta('callsign', ...)`) when the officer is online.

All framework branching lives in `ps_lib/bridge/framework/esx/*` and the
compatibility views — the MDT backend files are framework-agnostic via the
`ps.*` bridge.
