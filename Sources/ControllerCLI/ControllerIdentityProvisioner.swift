import Foundation

public enum ControllerIdentityProvisioningError: Error, Equatable, Sendable {
  case securityToolFailed(Int32)
}

public struct ControllerIdentityProvisioner: Sendable {
  public init() {}

  public func create(
    label: String,
    trustedExecutableURL: URL
  ) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = [
      "create-keypair",
      "-a", "rsa",
      "-s", "2048",
      "-d", "3650",
      "-T", trustedExecutableURL.path,
      label,
    ]
    try process.run()
    process.waitUntilExit()
    let exitCode = process.terminationStatus
    guard exitCode == 0 else {
      throw ControllerIdentityProvisioningError.securityToolFailed(exitCode)
    }
  }
}
