# Validate XCUITest before locking the injection backend

XCUITest and `XCUIDevice.shared.location` will be the first Injection Backend candidate, but only a minimal physical-device probe will initially depend on it. The controller protocol remains backend-neutral, and XCUITest becomes the first-round backend only if the probe can repeatedly apply, replace, and clear static coordinates while maintaining a sufficiently stable session; otherwise, another Apple-supported development mechanism can replace it without redesigning the iPhone app or Controller Link.
