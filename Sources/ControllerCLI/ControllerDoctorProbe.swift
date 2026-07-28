import ControllerLink
import Foundation

public struct ControllerDoctorCommandInvocation: Equatable, Sendable {
  public let executable: String
  public let arguments: [String]
  public let environmentOverrides: [String: String]

  public init(
    executable: String,
    arguments: [String],
    environmentOverrides: [String: String] = [:]
  ) {
    self.executable = executable
    self.arguments = arguments
    self.environmentOverrides = environmentOverrides
  }
}

public enum ControllerDoctorCommandResult: Equatable, Sendable {
  case exited(status: Int32, output: String)
  case failedToLaunch
}

public protocol ControllerDoctorCommandExecuting: Sendable {
  func execute(_ invocation: ControllerDoctorCommandInvocation) -> ControllerDoctorCommandResult
}

public struct FoundationControllerDoctorCommandExecutor: ControllerDoctorCommandExecuting {
  private static let inheritedEnvironmentKeys = [
    "HOME", "TMPDIR", "USER", "LOGNAME", "PATH", "LANG", "LC_ALL", "LC_CTYPE",
  ]
  private static let maximumCapturedBytes = 128 * 1_024

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
    _ invocation: ControllerDoctorCommandInvocation
  ) -> ControllerDoctorCommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: invocation.executable)
    process.arguments = invocation.arguments
    process.environment = Self.sanitizedEnvironment(
      inherited: ProcessInfo.processInfo.environment,
      overrides: invocation.environmentOverrides
    )

    // Probe output can include device and signing identifiers. It is retained
    // only long enough to derive typed facts and is never emitted by doctor.
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    do {
      try process.run()
    } catch {
      return .failedToLaunch
    }
    let rawData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let boundedData = rawData.prefix(Self.maximumCapturedBytes)
    return .exited(
      status: process.terminationStatus,
      output: String(decoding: boundedData, as: UTF8.self)
    )
  }
}

public struct FoundationControllerDoctorProbe: Sendable {
  private static let timeoutSeconds = "15"

  private let executor: any ControllerDoctorCommandExecuting
  private let controllerIdentityIsReady: @Sendable (String) -> Bool

  public init(
    executor: any ControllerDoctorCommandExecuting = FoundationControllerDoctorCommandExecutor(),
    controllerIdentityIsReady: @escaping @Sendable (String) -> Bool = { label in
      (try? KeychainTLSIdentity.load(label: label)) != nil
    }
  ) {
    self.executor = executor
    self.controllerIdentityIsReady = controllerIdentityIsReady
  }

  public func snapshot(
    configuration: ControllerDoctorConfiguration
  ) -> ControllerDoctorSnapshot {
    let activeDeveloperDirectory = successfulOutput(
      executor.execute(
        ControllerDoctorCommandInvocation(
          executable: "/usr/bin/xcode-select",
          arguments: ["-p"]
        )
      )
    )
    let xcodeVersion = successfulOutput(
      executeXcrun(["xcodebuild", "-version"], configuration: configuration)
    )
    let firstLaunchReady = isSuccessful(
      executeXcrun(
        ["xcodebuild", "-checkFirstLaunchStatus"],
        configuration: configuration
      )
    )

    let deviceState: ControllerDoctorDeviceState
    if let device = nonempty(configuration.device) {
      deviceState = Self.classifyDeviceResult(
        executeXcrun(
          [
            "devicectl", "device", "simulate", "location", "list",
            "--device", device,
            "--quiet", "--timeout", Self.timeoutSeconds,
          ],
          configuration: configuration
        )
      )
    } else {
      deviceState = .notConfigured
    }

    let signingResult = executor.execute(
      ControllerDoctorCommandInvocation(
        executable: "/usr/bin/security",
        arguments: ["find-identity", "-v", "-p", "codesigning"]
      )
    )

    return ControllerDoctorSnapshot(
      activeDeveloperDirectory: activeDeveloperDirectory,
      xcodeVersion: xcodeVersion,
      firstLaunchReady: firstLaunchReady,
      deviceState: deviceState,
      signingReady: signingIsReady(signingResult),
      controllerIdentityReady: controllerIdentityIsReady(configuration.identityLabel)
    )
  }

  static func classifyDeviceResult(
    _ result: ControllerDoctorCommandResult
  ) -> ControllerDoctorDeviceState {
    guard case .exited(let status, let output) = result else {
      return .unavailable
    }
    guard status == 0 else {
      let normalized = output.lowercased()
      if normalized.contains("developer mode")
        && (normalized.contains("disabled") || normalized.contains("enable"))
      {
        return .developerModeDisabled
      }
      if normalized.contains("developer disk image")
        || normalized.contains("ddi")
        || normalized.contains("device support")
      {
        return .developerDiskImageIncompatible
      }
      return .unavailable
    }
    return .available
  }

  private func executeXcrun(
    _ arguments: [String],
    configuration: ControllerDoctorConfiguration
  ) -> ControllerDoctorCommandResult {
    executor.execute(
      ControllerDoctorCommandInvocation(
        executable: "/usr/bin/xcrun",
        arguments: arguments,
        environmentOverrides: [
          "DEVELOPER_DIR": configuration.developerDirectory
        ]
      )
    )
  }

  private func isSuccessful(_ result: ControllerDoctorCommandResult) -> Bool {
    guard case .exited(let status, _) = result else {
      return false
    }
    return status == 0
  }

  private func successfulOutput(_ result: ControllerDoctorCommandResult) -> String? {
    guard case .exited(let status, let output) = result, status == 0 else {
      return nil
    }
    return nonempty(output)
  }

  private func signingIsReady(_ result: ControllerDoctorCommandResult) -> Bool {
    guard case .exited(let status, let output) = result, status == 0 else {
      return false
    }
    return output.range(
      of: #"[1-9][0-9]* valid identities found"#,
      options: [.regularExpression, .caseInsensitive]
    ) != nil
  }

  private func nonempty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }
}
