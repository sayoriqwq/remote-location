# Define simulation stop independently from physical recovery

For the public Xcode 27 `devicectl` Injection Backend selected by ADR-0009, clear succeeds only when `devicectl device simulate location clear` exits successfully. Stop immediately invalidates active, Applied, and Verified Simulation state, while a previously received coordinate remains an explicitly identified last observation; a fresh physical Core Location callback is best-effort diagnostic evidence rather than a clear deadline because Apple's public contracts do not tie callback delivery to simulation removal.
