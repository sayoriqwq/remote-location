# Use Xcode 27 beta for the current execution baseline

Status: Accepted

Date: 2026-07-28

## Context

ADR 0005 recorded Xcode 26.6 as the original personal-environment baseline. After the Mac moved to macOS 27 beta, that Xcode application could no longer open. The physical-device GPX baseline was completed with Xcode 27 beta 4 while the device, iOS version, wired connection, Developer Mode, and DDI assumptions remained unchanged.

## Decision

The first-round execution baseline uses Xcode 27.0 beta 4, build 27A5228h, from `/Applications/Xcode-beta.app`. Xcode-related commands select that developer directory explicitly and do not change the global `xcode-select` setting.

This is a replacement within the existing single-personal-environment boundary, not an added compatibility target. The project does not promise simultaneous support for Xcode 26.6 or any other Xcode release.

## Consequences

- Physical-device build, GPX, and XCUITest evidence must identify the Xcode 27 beta build used.
- Generated projects and source must remain free of local development-team, account, certificate, and device identifiers.
- A later toolchain change requires another explicit baseline decision and targeted re-verification.
