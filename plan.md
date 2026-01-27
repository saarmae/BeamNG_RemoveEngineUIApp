# BeamNG Remove Engine UI App — Implementation Plan

## 1. Repository and Tooling Prep
- [ ] Keep `BrebRandomVehConfig.zip` ignored locally (reference-only asset).
- [ ] Create a clean workspace structure mirroring the reference mod (`ui`, `lua`, `mod_info`, `Licenses`).
- [ ] Add scaffolding scripts (optional) for packaging into `RemoveEngine.zip`.

## 2. UI Module (`ui/modules/apps/RemoveEngine`)
- [ ] Define `app.json` per the README spec (dom element, directive name, default dimensions, description, preview image).
- [ ] Build `app.js` directive:
  - Register `removeEngine` on `beamng.apps`.
  - Initialize scope state (`vehicleId`, `engineSlot`, `engineState`, `busy`, `error`).
  - Subscribe to vehicle/stream updates to refresh state when cars change.
  - Implement `refreshState()` that calls the Lua helper for slot info.
  - Implement CTA handler (`setEngineEmpty()`) that dispatches the Lua `setEngineEmpty` command and handles promise resolution and error states.
  - Handle cleanup with `$destroy` and stream removal.
- [ ] Create HTML template (inline within directive or external) containing status text, tooltip, and action button with proper enable/disable cues.
- [ ] Add `app.png` preview asset (320×180) with consistent branding.
- [ ] Optionally extract repeated styles to a `styles.css` referenced by the template for easier maintenance.

## 3. Lua Extension (`lua/ge/extensions/core_RemoveEngine.lua`)
- [ ] Implement module registration boilerplate (return table with exposed functions, add to `extensions` namespace).
- [ ] Implement `getEngineSlotInfo()`:
  - Fetch the player vehicle (`be:getPlayerVehicle(0)`), guard against nil.
  - Inspect the vehicle’s part config to locate an engine slot (`mainEngine` or `type == "engine"`).
  - Detect whether the slot currently uses the empty part; return structured table consumed by the UI.
- [ ] Implement `setEngineEmpty()`:
  - Validate current vehicle + engine slot + available empty part.
  - Use `extensions.core_vehicle_manager.replacePart` (or equivalent) to swap the slot to `"empty"`.
  - Reapply the config and return success/failure details.
- [ ] Add logging helpers (`log('I', 'BREngineRemoval', ...)`) for troubleshooting.

## 4. Wiring UI ↔ Lua
- [ ] Ensure `app.js` calls `bngApi.engineLua('return extensions.core_BREngineRemoval.getEngineSlotInfo()')` with JSON serialization for data.
- [ ] Ensure button click executes `extensions.core_BREngineRemoval.setEngineEmpty()` and handles response JSON.
- [ ] Gracefully handle failures (toast text, UI error state) and re-run `refreshState()` on success.

## 5. Packaging & Metadata
- [ ] Populate `mod_info/info.json` with mod metadata (name, version, author, description).
- [ ] Include any license files for reused art assets under `Licenses/`.
- [ ] Zip the directories into `RemoveEngine.zip` once functionality is verified (zip remains untracked per `.gitignore`).

## 6. Testing Checklist
- [ ] Add the app in BeamNG’s UI and verify preview + description.
- [ ] Spawn several vehicles (stock, modded) to ensure engine detection works.
- [ ] Validate button states: enabled only when applicable, disabled otherwise.
- [ ] Press the button and confirm vehicle loses engine power; verify log outputs show success.
- [ ] Reset vehicles and switch between them to ensure state refresh works.
- [ ] Intentionally trigger failure paths (e.g., vehicle without engine slot) and confirm user-facing errors appear.

## 7. Release Steps
- [ ] Update `readme.MD` with any deviations from the spec.
- [ ] Commit UI + Lua source, preview image references, and metadata.
- [ ] Tag a release or upload `RemoveEngine.zip` to BeamNG repo once testing passes.
