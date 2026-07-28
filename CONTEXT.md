# Location Simulation Learning

This context covers learning and experimenting with location-aware iOS behavior through Apple-supported development and testing workflows.

## Language

**Simulated Location（模拟位置）**:
A location supplied to an app under test through Apple's development environment. It is distinct from the device owner's real location and does not imply changing location system-wide for other apps.
_Avoid_: Virtual Location, Fake GPS, Location Spoofing

**Selected Location（待应用位置）**:
A single coordinate chosen inside the learning app and awaiting application through the Simulation Controller. Selection alone never represents a Simulated Location or an Observed Location.
_Avoid_: Scenario Location, Simulated Location

**Simulation Controller（模拟控制器）**:
The developer-side participant that applies a selected location to the Active Test Device through the current Xcode development environment.
_Avoid_: iPhone App, GPS Spoofer

**Injection Backend（注入后端）**:
The replaceable part of the Simulation Controller that translates generic simulation requests into a location-testing mechanism provided by the active developer environment.
_Avoid_: Simulation Controller, Permanent XCUITest Dependency

**Controller Link（控制器连接）**:
The trusted local connection that carries simulation requests and execution status between the learning app and its Simulation Controller.
_Avoid_: Cloud Service, USB Tunnel

**Trusted Controller（可信控制器）**:
A Simulation Controller whose identity the learning app accepted through explicit one-time pairing and remembers for future Controller Links.
_Avoid_: Discovered Controller, User Account

**Active Test Device（活动测试设备）**:
The single physical iPhone currently selected for the developer workflow and eligible to receive simulation requests.
_Avoid_: Device Fleet, Concurrent Target

**Simulation Capability（模拟能力）**:
The consumer-agnostic ability to request, apply, stop, and report a Simulated Location through the active Xcode/devicectl developer workflow. It does not include validating how any particular app consumes that location.
_Avoid_: App Compatibility, Cross-App Guarantee

**Static Simulation（静态模拟）**:
A simulation that holds one coordinate until the developer replaces or stops it. Movement, speed, and route progression are outside this concept.
_Avoid_: Route Playback, Journey Simulation

**Stopped Simulation（已停止模拟）**:
A Static Simulation that its Injection Backend reports is no longer active. It invalidates Applied Simulation and Verified Simulation, while the latest Observed Location may remain as an explicitly identified last observation.
_Avoid_: Restored Physical Location, Cleared Observation

**Observed Location（观测位置）**:
The most recent Core Location value the learning app receives while in use. It can verify the app's own result but is not evidence of Cross-App Propagation.
_Avoid_: Applied Location, Device Truth

**Applied Simulation（已应用模拟）**:
A Static Simulation that the active Injection Backend reports it has set for the Active Test Device. This is an execution acknowledgement, not proof of the resulting location.
_Avoid_: Verified Simulation, Cross-App Success

**Verified Simulation（已验证模拟）**:
An Applied Simulation whose selected coordinate is subsequently matched by a fresh Observed Location in the learning app. This is the required first-round success outcome and is not evidence of Cross-App Propagation.
_Avoid_: Backend Success, Cross-App Propagation

**Cross-App Propagation（跨 App 传播）**:
An observed condition where an app other than the learning app reports a location consistent with the active Simulated Location. It is measured independently for each app rather than assumed to be device-wide.
_Avoid_: Cross-App Control, Guaranteed System Override
