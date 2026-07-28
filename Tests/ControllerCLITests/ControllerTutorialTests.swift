import ArgumentParser
import XCTest

@testable import ControllerCLI

final class ControllerTutorialTests: XCTestCase {
  func testTutorialCoversTheCurrentReadOnlySetupAndSimulationWorkflow() throws {
    let output = ControllerTutorial.output

    for requiredText in [
      "open Xcode",
      "Trust",
      "Developer Mode",
      "automatic signing",
      "seven days",
      "devicectl",
      "link identity create",
      "link serve",
      "Apply",
      "Verify",
      "Stop",
      "Location",
      "Local Network",
    ] {
      XCTAssertTrue(output.localizedCaseInsensitiveContains(requiredText), requiredText)
    }
    XCTAssertFalse(output.localizedCaseInsensitiveContains("XCUITest"))
    XCTAssertFalse(output.localizedCaseInsensitiveContains("sudo"))
    XCTAssertFalse(output.localizedCaseInsensitiveContains("xcode-select --switch"))
  }

  func testDoctorAndTutorialAreRegisteredSubcommands() throws {
    XCTAssertTrue(
      try RemoteLocationControllerCommand.parseAsRoot(["doctor"])
        is RemoteLocationControllerCommand.Doctor
    )
    XCTAssertTrue(
      try RemoteLocationControllerCommand.parseAsRoot(["tutorial"])
        is RemoteLocationControllerCommand.Tutorial
    )
  }
}
