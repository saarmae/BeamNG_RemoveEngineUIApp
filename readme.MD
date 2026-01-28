# BeamNG Remove Engine UI App — Specification

## 1. Overview
- **Objective:** Ship a BeamNG UI app that lets a player remove the currently spawned vehicle’s engine with one click. The app now focuses on a single semi-transparent button that reflects engine state and triggers the Empty swap—even on vehicles that never defined a literal `empty` part.
- **Audience:** BeamNG players who want a rapid way to disable engines (e.g., for towing scenarios, cinematic shots, or challenge setups) without navigating the parts configurator.
- **Primary Use Case:** Supplement soapbox, downhill, and other BeamNG challenge mods that expect you to strip engines before a run so you can stay in the flow instead of diving into the parts configurator.
- **Reference Material:** The bundled sample UI app demonstrates how to package AngularJS-based BeamNG UI modules and send Lua commands via `bngApi.engineLua`. Match its project layout while tailoring functionality to engine removal.

BeamNG normally forces you through the Parts Configurator (or a trip back to the garage) whenever an event requires an empty engine slot. That workflow kills momentum, especially during downhill challenge retries or cinematic shoots where you constantly swap vehicles. Remove Engine exists to collapse that friction into a single always-visible CTA so you stay trackside and avoid rummaging through part trees between runs.

## 2. Functional Requirements
1. Display a compact widget (≈450 × 90 px default footprint) named “Remove Engine”.
2. Render a single primary button labeled `Set Engine To Empty` that fills the widget and mirrors the engine state through its label and enablement.
3. Enabled state appears only when the active vehicle exposes a compatible engine slot that is not already empty. Disabled state text flips to `Engine Already Empty` or `Unavailable` based on the scenario.
4. On click, issue a Lua command that sets the engine slot to BeamNG’s user-empty state (empty string) so the result sticks even if no literal `empty` part exists, then refresh the UI state once the operation completes.
5. Handle vehicle changes in real time (when the player swaps cars, respawns, or resets) by re-evaluating the engine slot.
6. Provide inline feedback directly via the button text (e.g., `Working...`, `Engine Already Empty`) instead of additional status panels, while still logging failures for diagnostics.

## 3. Non-Goals
- No bulk operations across multiple vehicles.
- No persistence of settings between sessions.
- No direct modification of non-engine powertrain parts.

## 4. UI/UX Specification
- **Layout:** Full-bleed Angular Material `md-button` centered in the widget. No auxiliary copy; the button’s label communicates all states so the control can shrink without clipping.
- **Visual cues:**
  - Semi-transparent mint background (`rgba(126, 214, 140, 0.55)`) with a frosted border for the enabled state.
  - Disabled state drops to `rgba(90, 98, 107, 0.45)` and updates the label (`Engine Already Empty`, `Unavailable`).
  - Busy state uses `rgba(90, 118, 147, 0.75)` plus the `Working...` label.
- **Accessibility:** High-contrast type and large uppercase lettering ensure readability; there is no tooltip because the button text remains self-explanatory even at reduced sizes.

## 5. File/Module Structure
```
ui/modules/apps/RemoveEngine/
  app.json          // App metadata, DOM element mount, default dimensions
  app.js            // AngularJS directive + controller logic
  app.png           // 320×180 preview tile (reuse palette of reference mod)
  styles.css        // (optional) extracted styles if inline styles become noisy
lua/ge/extensions/core_RemoveEngine.lua // Lua helper invoked by the UI
mod_info/info.json  // Standard BeamNG mod metadata
Licenses/*          // Attributions if reusing assets
```

## 6. App.json Contract
- `domElement`: `<remove-engine></remove-engine>`
- `directive`: `removeEngine`
- `name`: `Remove Engine`
- `description`: “Swap the current vehicle’s engine for the Empty part with one click.”
- `css`: mirror the reference footprint but adjust height to ~120 px to fit the status text.
- `preserveAspectRatio`: `false` to allow free resizing.

## 7. AngularJS Controller Logic (app.js)
1. Register `removeEngine` directive on `beamng.apps`.
2. On link:
   - Subscribe to `$scope.$on('app:vehicleChanged', …)` and `StreamsManager.add` for `vehicles` or `electrics` stream (the same source the reference mod uses for updates) to know when the active vehicle changes.
   - Maintain controller state:
     ```js
     scope.state = {
       vehicleId: null,
       engineSlot: null,
       engineState: 'unknown', // 'installed' | 'empty' | 'missing'
       busy: false,
       error: null
     };
     ```
3. Implement `refreshState()` that:
   - Calls `bngApi.engineLua('return extensions.core_RemoveEngine.getEngineSlotInfo()')`.
   - Expects a payload `{ vehicleId, engineSlotId, slotName, isEmpty, partName }`.
   - Updates UI bindings accordingly.
4. Button handler `setEngineEmpty()`:
   - Guard against `busy` or incompatible state.
    - Call `bngApi.engineLua('extensions.core_RemoveEngine.setEngineEmpty()')`.
   - Show transient status: `busy = true` and disable CTA.
   - When promise resolves, call `refreshState()`; on rejection, show error text.
5. Cleanup: on `$destroy`, unsubscribe from streams.

## 8. Lua Helper (core_RemoveEngine.lua)
- Lives under `lua/ge/extensions/` so it can be referenced via `extensions.core_RemoveEngine`.
- Responsibilities:
  1. Identify the player’s active vehicle (`be:getPlayerVehicle(0)`).
  2. Inspect its part configuration via `v.config.parts` or `extensions.core_vehicle_manager.getPartConfig(vehicleId)`.
  3. Determine the engine slot name (usually `"mainEngine"`, but fall back to searching for slots with `type == "engine"`).
   4. Provide `getEngineSlotInfo()` returning structured data for the UI.
   5. Provide `setEngineEmpty()` that:
     - Validates a compatible slot exists and supports BeamNG’s user-empty (`''`) assignment even if no explicit `empty` part was authored.
      - Uses `extensions.core_vehicle_partmgmt.setConfig({ parts = { [slotName] = '' } }, true)` so the slot system treats it as a user request to leave the slot blank, then reapplies the configuration.
     - Returns success/failure with descriptive messages for UI display.
- Include graceful fallbacks when the empty part is unavailable (some mods may not expose it) and send descriptive error strings.

## 9. Error & Edge Case Handling
- **No vehicle spawned:** Disable button, show “Spawn a vehicle to continue.”
- **Vehicle lacks engine slot:** Disable button, show “This vehicle has no removable engine slot.”
- **Already empty:** Disable button, show “Engine already removed.”
- **Lua failure:** Display the error text for 5 s and log via `log('E', 'RemoveEngine', message)`.
- **Vehicle changed mid-operation:** Cancel the in-flight promise, refresh state for the new vehicle.

## 10. Packaging & Distribution
- Follow the same zip layout as the reference mod: top-level folders `ui`, `lua`, `mod_info`, `Licenses`, zipped with 7-Zip (or equivalent) so BeamNG recognizes the archive immediately.
- `mod_info/info.json` should include:
  ```json
  {
    "name": "Remove Engine",
    "author": "Khodar",
    "version": "1.0.0",
    "description": "Dashboard UI button that swaps the active engine to Empty for soapbox and downhill challenges.",
    "dependencies": []
  }
  ```
- Provide a 320×180 `app.png` preview registered in `app.json` so the app shows correctly in the selector.

## 11. Build & Installation Workflow
1. From the repo root, rebuild the distributable after making code or asset changes with 7-Zip:
   ```powershell
   "C:\Program Files\7-Zip\7z.exe" a -tzip RemoveEngine.zip lua mod_info ui
   ```
2. Copy the refreshed `RemoveEngine.zip` into BeamNG’s user mods folder, typically `C:\Users\<you>\AppData\Local\BeamNG.drive\current\mods`.
3. Launch BeamNG, open the UI Apps menu, and ensure the updated “Remove Engine” tile loads (reload the UI layout if needed).
4. Add the widget to a dashboard, spawn a few vehicles, and verify the button state flips appropriately before distributing the zip elsewhere.

## 12. Testing Checklist
- [ ] App appears in the in-game UI app selector with correct name and preview.
- [ ] Button enables/disables as vehicles with/without engines are spawned.
- [ ] Pressing the button installs the Empty engine part and the vehicle loses power.
- [ ] Resetting or switching vehicles refreshes the UI state within one tick.
- [ ] Errors (e.g., intentionally remove empty part definition) display friendly text and do not spam the console.
- [ ] No Lua stack traces or Angular digest errors appear in the BeamNG console.

## 13. Future Enhancements (Optional)
- Add hotkeys to trigger engine removal without opening the UI app.
- Allow selecting other removable powertrain components (transmission, driveshaft) via a dropdown.
- Provide an auto-remove toggle that triggers whenever a vehicle spawns.
