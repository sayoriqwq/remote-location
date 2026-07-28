# Use a local-network controller link

The iPhone app and Mac Simulation Controller will discover each other with Bonjour and exchange simulation requests and status over a TLS-protected local-network connection. This keeps the integration on Apple-supported networking APIs and avoids coupling control messages to USB-specific forwarding, while the separate Xcode device connection remains responsible for the developer test session.

Amendment: under ADR-0009, the separate Xcode device connection is used by the public `devicectl` Injection Backend; no long-running test session or runner control channel remains in production.
