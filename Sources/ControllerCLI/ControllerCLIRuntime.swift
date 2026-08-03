import Foundation
import SimulationDiagnostics
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
    executor: any DevicectlCommandExecuting = FoundationDevicectlCommandExecutor(),
    diagnostics: SimulationDiagnosticRecorder? = nil
  ) -> ControllerCLIRunner {
    let recorder = diagnostics ?? makeDiagnostics(environment: environment)
    return ControllerCLIRunner(
      controller: makeController(
        device: device,
        developerDirectory: developerDirectory,
        environment: environment,
        executor: executor,
        diagnostics: recorder
      ),
      diagnostics: recorder
    )
  }

  public static func makeController(
    device: String? = nil,
    developerDirectory: String? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    executor: any DevicectlCommandExecuting = FoundationDevicectlCommandExecutor(),
    diagnostics: SimulationDiagnosticRecorder? = nil
  ) -> SimulationController {
    let configuration = resolveConfiguration(
      device: device,
      developerDirectory: developerDirectory,
      environment: environment
    )

    let diagnostics = diagnostics ?? makeDiagnostics(environment: environment)
    return SimulationController(
      backend: DevicectlInjectionBackend(
        device: configuration.device ?? "",
        developerDirectory: configuration.developerDirectory,
        executor: executor,
        diagnostics: diagnostics
      ),
      diagnostics: diagnostics
    )
  }

  public static func makeDiagnostics(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> SimulationDiagnosticRecorder {
    SimulationDiagnosticRecorder(
      side: .macController,
      directory: SimulationDiagnosticRecorder.defaultDirectory(environment: environment)
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

  static func runServeLifecycle(
    seconds: Double,
    controller: SimulationController,
    sleep: @Sendable (Double) async throws -> Void = { duration in
      try await Task.sleep(for: .seconds(duration))
    },
    diagnostics: SimulationDiagnosticRecorder? = nil,
    report: @Sendable (ControllerCLIResult) async -> Void
  ) async throws {
    if let diagnostics {
      await diagnostics.record(kind: "controller.lifecycle.serve-started")
    }
    do {
      try await sleep(seconds)
    } catch {
      await reportServeCleanup(
        using: controller,
        diagnostics: diagnostics,
        interrupted: true,
        report: report
      )
      throw error
    }
    await reportServeCleanup(
      using: controller,
      diagnostics: diagnostics,
      interrupted: false,
      report: report
    )
  }

  private static func reportServeCleanup(
    using controller: SimulationController,
    diagnostics: SimulationDiagnosticRecorder?,
    interrupted: Bool,
    report: @Sendable (ControllerCLIResult) async -> Void
  ) async {
    await diagnostics?.record(
      kind: interrupted
        ? "controller.lifecycle.interrupted-shutdown-cleanup-started"
        : "controller.lifecycle.shutdown-cleanup-started"
    )
    let result = await ControllerCLIRunner(
      controller: controller,
      diagnostics: diagnostics
    ).run(
      .reset(requestID: UUID())
    )
    await report(result)
    await diagnostics?.record(
      kind: interrupted
        ? "controller.lifecycle.interrupted-shutdown-cleanup-finished"
        : "controller.lifecycle.shutdown-cleanup-finished",
      fields: [
        "exitCode": .integer(Int64(result.exitCode)),
        "outcome": .text(result.exitCode == 0 ? "success" : "failed"),
      ]
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
