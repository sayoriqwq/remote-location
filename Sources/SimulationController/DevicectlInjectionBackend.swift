import Foundation
import LocationDomain

public struct DevicectlCommandInvocation: Equatable, Sendable {
  public let arguments: [String]
  public let environmentOverrides: [String: String]

  public init(
    arguments: [String],
    environmentOverrides: [String: String]
  ) {
    self.arguments = arguments
    self.environmentOverrides = environmentOverrides
  }
}

public enum DevicectlCommandExecutionResult: Equatable, Sendable {
  case exited(Int32)
  case failedToLaunch
}

public protocol DevicectlCommandExecuting: Sendable {
  func execute(
    _ invocation: DevicectlCommandInvocation
  ) -> DevicectlCommandExecutionResult
}

public struct FoundationDevicectlCommandExecutor: DevicectlCommandExecuting {
  private static let inheritedEnvironmentKeys = [
    "HOME", "TMPDIR", "USER", "LOGNAME", "PATH", "LANG", "LC_ALL", "LC_CTYPE",
  ]

  public init() {}

  static func sanitizedEnvironment(
    inherited: [String: String],
    overrides: [String: String]
  ) -> [String: String] {
    var environment: [String: String] = [:]
    for key in inheritedEnvironmentKeys {
      if let value = inherited[key] {
        environment[key] = value
      }
    }
    environment["PATH"] = environment["PATH"] ?? "/usr/bin:/bin"
    for (key, value) in overrides {
      environment[key] = value
    }
    return environment
  }

  public func execute(
    _ invocation: DevicectlCommandInvocation
  ) -> DevicectlCommandExecutionResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = invocation.arguments

    process.environment = Self.sanitizedEnvironment(
      inherited: ProcessInfo.processInfo.environment,
      overrides: invocation.environmentOverrides
    )

    // devicectl output can contain device identifiers. The backend exposes only
    // stable domain status and never forwards raw tool output to the app or logs.
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      return .failedToLaunch
    }
    process.waitUntilExit()
    return .exited(process.terminationStatus)
  }
}

public actor DevicectlInjectionBackend: InjectionBackend {
  private static let timeoutSeconds = "15"

  private let device: String
  private let developerDirectory: String
  private let executor: any DevicectlCommandExecuting

  public init(
    device: String,
    developerDirectory: String = "/Applications/Xcode-beta.app/Contents/Developer",
    executor: any DevicectlCommandExecuting = FoundationDevicectlCommandExecutor()
  ) {
    self.device = device.trimmingCharacters(in: .whitespacesAndNewlines)
    self.developerDirectory = developerDirectory
    self.executor = executor
  }

  public func readiness() -> InjectionBackendReadiness {
    guard !device.isEmpty else {
      return .unavailable(.noActiveDevice)
    }

    switch run(
      [
        "devicectl", "device", "simulate", "location", "list",
        "--device", device,
        "--quiet", "--timeout", Self.timeoutSeconds,
      ]
    ) {
    case .exited(0):
      return .ready
    case .exited, .failedToLaunch:
      return .unavailable(.backendUnavailable)
    }
  }

  public func execute(_ command: InjectionBackendCommand) -> InjectionBackendResult {
    guard !device.isEmpty else {
      return .failed(requestID: command.requestID, reason: .noActiveDevice)
    }

    switch command {
    case .apply(let requestID, let location):
      let result = run(
        [
          "devicectl", "device", "simulate", "location", "coordinate",
          "--device", device,
          "--latitude=\(format(location.latitude))",
          "--longitude=\(format(location.longitude))",
          "--quiet", "--timeout", Self.timeoutSeconds,
        ]
      )
      guard result == .exited(0) else {
        return .failed(requestID: requestID, reason: .backendUnavailable)
      }
      return .applied(requestID: requestID, location: location)

    case .clear(let requestID):
      let result = run(
        [
          "devicectl", "device", "simulate", "location", "clear",
          "--device", device,
          "--quiet", "--timeout", Self.timeoutSeconds,
        ]
      )
      guard result == .exited(0) else {
        return .failed(requestID: requestID, reason: .clearFailed)
      }
      return .cleared(requestID: requestID)
    }
  }

  private func run(_ arguments: [String]) -> DevicectlCommandExecutionResult {
    executor.execute(
      DevicectlCommandInvocation(
        arguments: arguments,
        environmentOverrides: ["DEVELOPER_DIR": developerDirectory]
      )
    )
  }

  private func format(_ coordinate: Double) -> String {
    String(
      format: "%.8f",
      locale: Locale(identifier: "en_US_POSIX"),
      coordinate
    )
  }
}

extension InjectionBackendCommand {
  fileprivate var requestID: UUID {
    switch self {
    case .apply(let requestID, _), .clear(let requestID):
      requestID
    }
  }
}
