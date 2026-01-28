# BeamNG Remove Engine UI App — Specification

## 1. Overview
- **Objective:** Ship a BeamNG UI app that lets a player remove the currently spawned vehicle’s engine with one click. The app inspects the active vehicle, shows whether its engine slot already uses the `empty`/user-empty state, and triggers the swap when requested—even on vehicles that never defined a literal `empty` part.
- **Audience:** BeamNG players who want a rapid way to disable engines (e.g., for towing scenarios, cinematic shots, or challenge setups) without navigating the parts configurator.
- **Primary Use Case:** Supplement soapbox, downhill, and other BeamNG challenge mods that expect you to strip engines before a run so you can stay in the flow instead of diving into the parts configurator.
- **Reference Material:** The bundled sample UI app demonstrates how to package AngularJS-based BeamNG UI modules and send Lua commands via `bngApi.engineLua`. Match its project layout while tailoring functionality to engine removal.

## 2. Functional Requirements
1. Display a compact widget (≈450 × 120 px default footprint) named “Remove Engine”.
2. Show current vehicle metadata: vehicle name, engine slot label, and engine status (`Installed`, `Already Empty`, or `Slot Missing`).
3. Provide a primary button labeled `Set Engine To Empty`.
   - Enabled only when the vehicle has a compatible engine slot and that slot is not already using the empty/user-empty state.
   - Disabled state text changes to `No Engine Slot` or `Already Empty` as appropriate.
4. On click, issue a Lua command that sets the engine slot to BeamNG’s user-empty state (empty string) so the result sticks even if no literal `empty` part exists, then refresh the UI state once the operation completes.
5. Handle vehicle changes in real time (when the player swaps cars, respawns, or resets) by re-evaluating the engine slot.
6. Surface errors (e.g., Lua failure, missing slot) as inline toast text under the button; auto-hide after 5 s.

## 3. Non-Goals
- No bulk operations across multiple vehicles.
- No persistence of settings between sessions.
- No direct modification of non-engine powertrain parts.

## 4. UI/UX Specification
- **Layout:** Horizontal stack—left column for status text, right column for the action button. Use the same Angular Material components as the reference mod for consistency with BeamNG’s UI system.
- **Visual cues:**
  - Neutral gray background (`#AAAABBBB`) for idle button.
  - Success flash to green (`#7ED68CBB`) when the engine is removed.
  - Error flash to red (`#FF6B6BBB`).
- **Accessibility:** Provide tooltip text (“Remove the current engine by installing the Empty part”). Ensure button text remains legible at the minimum widget width.

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
- Follow the same zip layout as the reference mod: top-level folders `ui`, `lua`, `mod_info`, `Licenses`.
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
1. From the repo root, rebuild the distributable after making code or asset changes:
   ```powershell
   py -3 -m zipfile -c RemoveEngine.zip lua ui mod_info
   ```
2. Copy the refreshed `RemoveEngine.zip` into BeamNG’s user mods folder, typically `C:\Users\<you>\AppData\Local\BeamNG.drive\current\mods`.
3. Launch BeamNG, open the UI Apps menu, and ensure the updated “Remove Engine” tile loads (reload the UI layout if needed).
4. Add the widget to a dashboard, spawn a few vehicles, and verify the status text/button states match expectations before distributing the zip elsewhere.

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
