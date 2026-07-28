# Remote Location first-round tutorial

This tutorial covers the current personal environment only. The production Injection Backend is Xcode 27's public `devicectl device simulate location` workflow; there is no production test runner or second backend.

## Prepare Xcode and the iPhone

1. Install the approved full Xcode and open it once to finish first-launch setup.
2. Connect and unlock the iPhone. Confirm **Trust** on both devices if prompted.
3. Enable **Developer Mode** in **Settings → Privacy & Security**, restart if prompted, and confirm it after restart.
4. Open the app project in Xcode and select automatic signing for an available development team. A Personal Team build can require rebuilding and reprovisioning every seven days.
5. Build, install, and launch **Remote Location Learning** on the iPhone.

Keep the Active Test Device selector private. Supply it with `--device` or the `REMOTE_LOCATION_DEVICE` environment variable. Supply the approved full-Xcode developer directory with `--developer-directory` or `REMOTE_LOCATION_DEVELOPER_DIR`; this project does not require changing the global `xcode-select` value.

## Diagnose without changing settings

Run:

```console
remote-location-controller doctor
```

Doctor checks the configured full Xcode/version, first-launch status, developer-directory mismatch, Active Test Device availability, Developer Mode or developer disk image failures, signing identity, Controller Link identity, and the App permission checkpoint. It uses fixed read-only commands, never prints raw device or signing output, and never changes Xcode, device, permission, or system settings.

Follow only the recovery step for a failed check. Location and Local Network decisions belong to iOS, so their authoritative status appears inside the Learning App.

## Pair and use the controller

Create the Keychain-backed controller identity once:

```console
remote-location-controller link identity create
```

Start the trusted local Controller Link and keep it open:

```console
remote-location-controller link serve
```

In the Learning App:

1. Allow **Location** and **Local Network** access, then enter the short-lived pairing code.
2. Choose one Selected Location with manual coordinates, the map, or place search. Selecting never applies automatically.
3. Tap **Apply Selected Location**. **Applied** means the `devicectl` backend acknowledged the request.
4. Wait for a fresh nearby observation. **Verified** means this Learning App observed the selected coordinate within its verification window; it is not a Cross-App Propagation guarantee.
5. Tap **Stop Simulation** to clear the static proxy. The last observed coordinate can remain visible and a fresh physical callback is not guaranteed immediately.

`remote-location-controller tutorial` prints the same compact workflow in the terminal.
