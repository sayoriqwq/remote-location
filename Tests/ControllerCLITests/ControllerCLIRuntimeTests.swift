import ControllerLink
import Foundation
import SimulationController
import XCTest

@testable import ControllerCLI

final class ControllerCLIRuntimeTests: XCTestCase {
  func testResolvesExplicitValuesBeforeEnvironmentAndDefaults() {
    let explicit = ControllerCLIRuntime.resolveConfiguration(
      device: " Explicit Device ",
      developerDirectory: " /Explicit/Xcode.app/Contents/Developer ",
      environment: [
        "REMOTE_LOCATION_DEVICE": "Environment Device",
        "REMOTE_LOCATION_DEVELOPER_DIR": "/Environment/Xcode.app/Contents/Developer",
      ]
    )
    let environment = ControllerCLIRuntime.resolveConfiguration(
      environment: [
        "REMOTE_LOCATION_DEVICE": " Environment Device ",
        "REMOTE_LOCATION_DEVELOPER_DIR": " /Environment/Xcode.app/Contents/Developer ",
      ]
    )
    let defaults = ControllerCLIRuntime.resolveConfiguration(environment: [:])

    XCTAssertEqual(explicit.device, "Explicit Device")
    XCTAssertEqual(explicit.developerDirectory, "/Explicit/Xcode.app/Contents/Developer")
    XCTAssertEqual(environment.device, "Environment Device")
    XCTAssertEqual(
      environment.developerDirectory,
      "/Environment/Xcode.app/Contents/Developer"
    )
    XCTAssertNil(defaults.device)
    XCTAssertEqual(
      defaults.developerDirectory,
      ControllerCLIRuntime.defaultDeveloperDirectory
    )
  }

  func testBuildsTheProductionControllerFromDevicectlConfiguration() async {
    let executor = RuntimeRecordingDevicectlExecutor(
      results: [.exited(0), .exited(0), .exited(0), .exited(0)]
    )
    let environment = [
      "REMOTE_LOCATION_DEVICE": "Active Test Device",
      "REMOTE_LOCATION_DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer",
    ]
    let controller = ControllerCLIRuntime.makeController(
      environment: environment,
      executor: executor
    )
    let handler = SimulationControllerCommandHandler(controller: controller)

    let status = await handler.handle(.status(requestID: UUID()))
    let applyID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    let applied = await handler.handle(
      .apply(requestID: applyID, latitude: 31.2304, longitude: 121.4737)
    )
    let stopID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    let stopped = await handler.handle(.stop(requestID: stopID))

    XCTAssertEqual(status, .ready(requestID: status.requestID))
    XCTAssertEqual(applied, .applied(requestID: applyID))
    XCTAssertEqual(stopped, .stopped(requestID: stopID))
    XCTAssertEqual(executor.invocations.count, 4)
    XCTAssertTrue(
      executor.invocations.allSatisfy {
        $0.environmentOverrides["DEVELOPER_DIR"]
          == "/Applications/Xcode-beta.app/Contents/Developer"
      }
    )
  }

  func testMissingDeviceConfigurationReportsNoActiveDeviceWithoutSpawningAProcess() async {
    let executor = RuntimeRecordingDevicectlExecutor(results: [])
    let runner = ControllerCLIRuntime.makeRunner(
      environment: [:],
      executor: executor
    )

    let result = await runner.run(.status)

    XCTAssertEqual(
      result,
      ControllerCLIResult(
        exitCode: 1,
        output: "No Active Test Device is configured. Pass --device or set REMOTE_LOCATION_DEVICE."
      )
    )
    XCTAssertTrue(executor.invocations.isEmpty)
  }
}

private final class RuntimeRecordingDevicectlExecutor:
  DevicectlCommandExecuting, @unchecked Sendable
{
  private let lock = NSLock()
  private var pendingResults: [DevicectlCommandExecutionResult]
  private var recordedInvocations: [DevicectlCommandInvocation] = []

  init(results: [DevicectlCommandExecutionResult]) {
    pendingResults = results
  }

  var invocations: [DevicectlCommandInvocation] {
    lock.withLock { recordedInvocations }
  }

  func execute(
    _ invocation: DevicectlCommandInvocation
  ) -> DevicectlCommandExecutionResult {
    lock.withLock {
      recordedInvocations.append(invocation)
      return pendingResults.removeFirst()
    }
  }
}
