import Foundation
import LocationDomain
import XCTest

@testable import SimulationController

final class DevicectlInjectionBackendTests: XCTestCase {
  func testReadinessUsesTheConfiguredDeviceAndXcodeToolchain() async {
    let executor = RecordingDevicectlCommandExecutor(results: [.exited(0)])
    let backend = DevicectlInjectionBackend(
      device: "Active Test Device",
      developerDirectory: "/Applications/Xcode-beta.app/Contents/Developer",
      executor: executor
    )

    let readiness = await backend.readiness()

    XCTAssertEqual(readiness, .ready)
    XCTAssertEqual(
      executor.invocations,
      [
        DevicectlCommandInvocation(
          arguments: [
            "devicectl", "device", "simulate", "location", "list",
            "--device", "Active Test Device",
            "--quiet", "--timeout", "15",
          ],
          environmentOverrides: [
            "DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer"
          ]
        )
      ]
    )
  }

  func testApplyBindsNegativeCoordinatesToTheirOptionsAndPreservesRequestIdentity() async throws {
    let executor = RecordingDevicectlCommandExecutor(results: [.exited(0)])
    let backend = DevicectlInjectionBackend(
      device: "Developer iPhone; do-not-run",
      developerDirectory: "/Applications/Xcode-beta.app/Contents/Developer",
      executor: executor
    )
    let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    let location = try SelectedLocation(latitude: -34.6037, longitude: -58.3816)

    let result = await backend.execute(.apply(requestID: requestID, location: location))

    XCTAssertEqual(result, .applied(requestID: requestID, location: location))
    XCTAssertEqual(
      executor.invocations.first?.arguments,
      [
        "devicectl", "device", "simulate", "location", "coordinate",
        "--device", "Developer iPhone; do-not-run",
        "--latitude=-34.60370000",
        "--longitude=-58.38160000",
        "--quiet", "--timeout", "15",
      ]
    )
  }

  func testClearSuccessAndFailureStayCorrelatedToTheirRequests() async {
    let successfulID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    let failedID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    let executor = RecordingDevicectlCommandExecutor(
      results: [.exited(0), .exited(1)]
    )
    let backend = DevicectlInjectionBackend(
      device: "Developer iPhone",
      developerDirectory: "/Applications/Xcode-beta.app/Contents/Developer",
      executor: executor
    )

    let success = await backend.execute(.clear(requestID: successfulID))
    let failure = await backend.execute(.clear(requestID: failedID))

    XCTAssertEqual(success, .cleared(requestID: successfulID))
    XCTAssertEqual(
      failure,
      .failed(requestID: failedID, reason: .clearFailed)
    )
    XCTAssertEqual(
      executor.invocations.first?.arguments,
      [
        "devicectl", "device", "simulate", "location", "clear",
        "--device", "Developer iPhone",
        "--quiet", "--timeout", "15",
      ]
    )
  }

  func testMissingDeviceAndLaunchFailureAreStableReadinessFailures() async {
    let unusedExecutor = RecordingDevicectlCommandExecutor(results: [])
    let missingDevice = DevicectlInjectionBackend(
      device: "   ",
      developerDirectory: "/Applications/Xcode-beta.app/Contents/Developer",
      executor: unusedExecutor
    )
    let failedExecutor = RecordingDevicectlCommandExecutor(results: [.failedToLaunch])
    let failedLaunch = DevicectlInjectionBackend(
      device: "Developer iPhone",
      developerDirectory: "/Applications/Xcode-beta.app/Contents/Developer",
      executor: failedExecutor
    )

    let missingReadiness = await missingDevice.readiness()
    let failedReadiness = await failedLaunch.readiness()

    XCTAssertEqual(missingReadiness, .unavailable(.noActiveDevice))
    XCTAssertTrue(unusedExecutor.invocations.isEmpty)
    XCTAssertEqual(failedReadiness, .unavailable(.backendUnavailable))
  }

  func testProductionExecutorDoesNotInheritControllerSecrets() {
    let environment = FoundationDevicectlCommandExecutor.sanitizedEnvironment(
      inherited: [
        "HOME": "/Users/developer",
        "PATH": "/usr/bin:/bin",
        "REMOTE_LOCATION_E2E_PAIRING_CODE": "123456",
        "REMOTE_LOCATION_RUNNER_CREDENTIAL": "private",
      ],
      overrides: [
        "DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer"
      ]
    )

    XCTAssertEqual(environment["HOME"], "/Users/developer")
    XCTAssertEqual(environment["PATH"], "/usr/bin:/bin")
    XCTAssertEqual(
      environment["DEVELOPER_DIR"],
      "/Applications/Xcode-beta.app/Contents/Developer"
    )
    XCTAssertNil(environment["REMOTE_LOCATION_E2E_PAIRING_CODE"])
    XCTAssertNil(environment["REMOTE_LOCATION_RUNNER_CREDENTIAL"])
  }
}

private final class RecordingDevicectlCommandExecutor:
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
