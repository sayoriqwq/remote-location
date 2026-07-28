# Validate XCUITest before locking the injection backend

_Status: Superseded by ADR-0009._

XCUITest and `XCUIDevice.shared.location` will be the first Injection Backend candidate, but only a minimal physical-device probe will initially depend on it. The controller protocol remains backend-neutral, and XCUITest becomes the first-round backend only if the probe can repeatedly apply, replace, and clear static coordinates while maintaining a sufficiently stable session; otherwise, another Apple-supported development mechanism can replace it without redesigning the iPhone app or Controller Link. ADR-0008 defines clear by the public proxy state independently from physical Core Location recovery.
