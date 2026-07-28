import Foundation
import SimulationController

public struct ControllerRuntimeConfiguration: Equatable, Sendable {
  public let device: String?
  public let developerDirectory: String

  public init(device: String?, developerDirectory: String) {
    self.device = device
    self.developerDirectory = developerDirectory
  }
}

public enum ControllerCLIRuntime {
  public static let deviceEnvironmentKey = "REMOTE_LOCATION_DEVICE"
  public static let developerDirectoryEnvironmentKey =
    "REMOTE_LOCATION_DEVELOPER_DIR"
  public static let defaultDeveloperDirectory =
    "/Applications/Xcode-beta.app/Contents/Developer"
  public static let e2ePairingCodeEnvironmentKey =
    "REMOTE_LOCATION_E2E_PAIRING_CODE"

  public static func makeRunner(
    device: String? = nil,
    developerDirectory: String? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    executor: any DevicectlCommandExecuting = FoundationDevicectlCommandExecutor()
  ) -> ControllerCLIRunner {
    ControllerCLIRunner(
      controller: makeController(
        device: device,
        developerDirectory: developerDirectory,
        environment: environment,
        executor: executor
      )
    )
  }

  public static func makeController(
    device: String? = nil,
    developerDirectory: String? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    executor: any DevicectlCommandExecuting = FoundationDevicectlCommandExecutor()
  ) -> SimulationController {
    let configuration = resolveConfiguration(
      device: device,
      developerDirectory: developerDirectory,
      environment: environment
    )

    return SimulationController(
      backend: DevicectlInjectionBackend(
        device: configuration.device ?? "",
        developerDirectory: configuration.developerDirectory,
        executor: executor
      )
    )
  }

  public static func resolveConfiguration(
    device: String? = nil,
    developerDirectory: String? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> ControllerRuntimeConfiguration {
    ControllerRuntimeConfiguration(
      device: nonempty(device) ?? nonempty(environment[deviceEnvironmentKey]),
      developerDirectory: nonempty(developerDirectory)
        ?? nonempty(environment[developerDirectoryEnvironmentKey])
        ?? defaultDeveloperDirectory
    )
  }

  private static func nonempty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }
}
