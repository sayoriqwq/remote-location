# Stage D integration evidence — 2026-07-28

## Scope

This record covers the integrated-candidate behavior for Issues #7, #8, and #9 under ADR-0009. It does not mark the issues accepted or closed; Stage D review and Lead adjudication remain separate.

## Automated verification

- `swift test`: 69 tests passed across Location Domain, Controller Link, Simulation Controller, and Controller CLI targets after the pairing and apply-readiness regressions were added.
- Simulator UI regression: the map-selection, search-selection, search empty/failure preservation, and permission-fixture journeys all passed together.
- A follow-up iOS 27 simulator regression passed for map selection → Done → enabled Apply. The assertion specifically prevents Controller Link discovery state from making a valid selected location permanently non-interactive.
- Generic iOS `build-for-testing` with signing disabled passed after the final backend fix.
- Doctor fixtures cover healthy Xcode, global Command Line Tools mismatch, incomplete first launch, no/unavailable device, Developer Mode disabled, incompatible developer disk image, unavailable signing, and missing Controller Link identity.
- The production doctor probe test records every invocation, permits only fixed read-only executables/arguments, checks sanitized process environment, and verifies that raw device, signing, account, and identity fixture values never enter the report.

## Physical-device batch

All identifiers, signing details, pairing material, and raw device output remain in owner-only temporary logs and are omitted here.

- Read-only doctor passed the configured full Xcode, first-launch, device availability, Developer Mode, developer disk image, signing, and Keychain-backed Controller Link identity checks. It reported the global Command Line Tools selection as a warning and did not change it.
- The current app signed, built, installed, and launched on the Active Test Device.
- After `D-IMPL-003`, the corrected app again signed, built, installed over the existing app, and launched successfully on the Active Test Device without requiring user interaction.
- A physical UI-test journey was attempted for Controller Link → map/search selection → apply/verify → stop. Xcode's physical UI-test runner exited with code 74 before establishing its test connection, so no test method or product assertion ran. This is recorded as unavailable infrastructure evidence, not a product failure or a blocker.
- The production CLI/backend then passed a negative-longitude apply A, a positive-longitude replacement B, stop, and an additional idempotent reset on the Active Test Device.
- The static simulation was cleared at the end. Owner-only short-lived pairing material used for the attempted test was explicitly removed after the forced test-server shutdown.

## Findings discovered during the batch

`D-IMPL-001` — fixed and verified: the initial backend passed negative numeric option values as separate `devicectl` arguments. The tool interpreted a negative longitude as another option and rejected it even though readiness remained healthy. Latitude and longitude now use one argument each (`--latitude=<value>` and `--longitude=<value>`). A regression test covers two negative coordinates, a direct physical probe confirmed the public syntax, and the production CLI passed the negative-longitude A → B → stop/reset sequence after the fix.

`D-IMPL-002` — fixed and verified: the macOS CLI authorization store requested Data Protection Keychain attributes intended for the app-side platform. A correct pairing code was redeemed, but persisting the resulting server authorization failed and the protocol collapsed that storage failure into a generic rejection. The macOS query now omits the incompatible attributes while the non-macOS accessibility policy remains intact. A real Keychain-backed server-session regression proves that a correct code both pairs and persists authorization.

`D-IMPL-003` — fixed and verified: Apply and Stop enablement incorrectly depended on momentary Controller Link readiness. A transient empty Bonjour result could disconnect an already trusted link and leave valid lifecycle actions permanently disabled. A selected location now enables Apply independently of discovery timing, an active applied request keeps Stop actionable, and both commands refresh the trusted link before sending. A Controller Link red/green regression covers transient discovery loss for both commands, and an iOS 27 UI regression proves that map selection followed by Done leaves Apply enabled. The corrected app was rebuilt, installed, and launched on the physical device.

## Evidence boundary

The simulator proves that manual, map, and search entry points replace one shared Selected Location and do not auto-apply, and now directly proves that map selection leaves Apply enabled. Domain and Controller Link tests prove that this shared selection reaches the same correlated apply path and that Apply recovers a trusted link after transient discovery loss. The physical batch proves the production backend's negative/positive apply, replacement, clear, and reset behavior, plus successful installation and launch of the corrected app. Because the physical UI-test method never started and no post-fix physical tap was performed, this record does **not** claim a completed physical tap-through of the map/search UI or a new physical App observation for those two selections. Earlier ADR-0009 evidence remains the physical A/B fresh-observation proof for the same sole backend.
