# Pinshift first-round tutorial

This tutorial covers the current personal environment only. The production Injection Backend is Xcode 27's public `devicectl device simulate location` workflow; there is no production test runner or second backend.

## Repository-local quick start

The repository contains a Nix Flake and direnv setup. It supplies Fish, jq, and XcodeGen while deliberately leaving Swift to the approved Xcode Beta toolchain. Approve the environment once after cloning or whenever `.envrc` changes:

```console
cd /Users/sayori/Desktop/remote-location
direnv allow
```

After that, the normal startup flow is:

```console
cd /Users/sayori/Desktop/remote-location
rl-install # once, and again only after controller source changes
rl-doctor
rl-start
```

`rl-install` creates a stable, signed controller executable and conservatively authorizes that exact executable to use the existing controller private key. The first migration can show one macOS Keychain approval; approve the signed controller permanently. It does not delete or replace the existing TLS identity, and it stops before changing Keychain if the signing requirement differs from the previous installation.

Daily commands never rebuild or re-sign the controller. `rl-start` keeps the trusted Controller Link open for one hour by default. Use `rl-start --seconds 86400` for a longer session and stop it with Control-C; the wrapper then performs an idempotent cleanup reset. `rl-reset` clears an active simulation without starting the link.

When exactly one paired physical iPhone is known to Xcode, these commands select it automatically without printing its private identifier. If discovery is ambiguous, copy `.env.example` to the Git-ignored `.env.local` and set `REMOTE_LOCATION_DEVICE` there.

## Prepare Xcode and the iPhone

1. Install the approved full Xcode and open it once to finish first-launch setup.
2. Connect and unlock the iPhone. Confirm **Trust** on both devices if prompted.
3. Enable **Developer Mode** in **Settings → Privacy & Security**, restart if prompted, and confirm it after restart.
4. Open the app project in Xcode and select automatic signing for an available development team. A Personal Team build can require rebuilding and reprovisioning every seven days.
5. Build, install, and launch **Pinshift** on the iPhone.

After that first signed build, renew the Personal Team app from the repository with:

```fish
rl-resign-app
```

🔏 Renews only when 24 hours or less remain, verifies the new profile, and updates the existing app.

Use `rl-resign-app --force` to request a newer profile immediately. The command temporarily moves
only profiles whose application identifier exactly matches `dev.sayori.remotelocation.learning`,
then asks Xcode automatic signing for a replacement. Before installation it verifies the candidate
code signature, bundle identifier, signing team, application prefix, and a strictly later expiration
date. It never uninstalls the device app. A pre-install failure restores the old cached profile;
successful renewals retain the old profile in a private repository-local backup under `.build/`.
Once installation begins, a timeout or disconnect is an uncertain remote outcome rather than a safe
rollback point. In that case the command keeps the new profile, signed candidate, and private logs for
inspection and does not claim that the existing device app remained unchanged.

Xcode must remain signed in to the Apple Account. Authentication expiry, two-factor authentication,
or updated developer agreements still require interaction in Xcode. Wi-Fi installation requires the
paired iPhone to remain visible to Xcode. A locked phone can defer only launch verification; unlock it
and run `rl-resign-app --launch-only`, or open Pinshift manually.

Keep the Active Test Device selector private. Supply it with `--device` or the `REMOTE_LOCATION_DEVICE` environment variable. Supply the approved full-Xcode developer directory with `--developer-directory` or `REMOTE_LOCATION_DEVELOPER_DIR`; this project does not require changing the global `xcode-select` value.

## Diagnose without changing settings

Run:

```console
remote-location-controller doctor
```

Doctor checks the configured full Xcode/version, first-launch status, developer-directory mismatch, Active Test Device availability, Developer Mode or developer disk image failures, signing identity, Controller Link identity, and the App permission checkpoint. It uses fixed read-only commands, never prints raw device or signing output, and never changes Xcode, device, permission, or system settings.

Follow only the recovery step for a failed check. Location and Local Network decisions belong to iOS, so their authoritative status appears inside the Learning App.

## Pair and use the controller

Install or update the repository-local signed controller:

```console
rl-install
```

Start the trusted local Controller Link and keep it open:

```console
rl-start
```

An iPhone that already trusts the preserved controller identity reconnects without a new six-digit code. A new or reset iPhone still performs the explicit one-time pairing flow.

In the Learning App:

1. Allow **Location** and **Local Network** access, then enter the short-lived pairing code.
2. Choose one Selected Location with manual coordinates, the map, or place search. Selecting never applies automatically.
3. Tap **Apply Selected Location**. **Applied** means the `devicectl` backend acknowledged the request.
4. Wait for a fresh nearby observation. **Verified** means this Learning App observed the selected coordinate within its verification window; it is not a Cross-App Propagation guarantee.
5. Tap **Stop Simulation** to clear the static proxy. The last observed coordinate can remain visible and a fresh physical callback is not guaranteed immediately.

`remote-location-controller tutorial` prints the same compact workflow in the terminal.
