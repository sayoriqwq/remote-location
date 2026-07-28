import Foundation
import XCTest

final class RepositoryV11RequirementsTests: XCTestCase {
  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  func testDailyHelpersUseOnlyTheInstalledController() throws {
    for helper in ["rl-start", "rl-doctor", "rl-reset"] {
      let contents = try String(
        contentsOf: repositoryRoot.appending(path: "bin/\(helper)"),
        encoding: .utf8
      )
      XCTAssertFalse(contents.contains("swift run"), "\(helper) must not compile on daily use")
      XCTAssertTrue(
        contents.contains("rl_controller_executable"),
        "\(helper) must resolve the verified installed controller"
      )
    }
  }

  func testInstallWorkflowIsExplicitAndNeverUsesAnAllowAllKeyACL() throws {
    let installerURL = repositoryRoot.appending(path: "bin/rl-install")
    XCTAssertTrue(
      FileManager.default.isExecutableFile(atPath: installerURL.path),
      "The repository must provide an executable rl-install workflow"
    )
    let contents = try String(contentsOf: installerURL, encoding: .utf8)
    XCTAssertFalse(contents.contains("create-keypair -A"))
    XCTAssertFalse(contents.contains("set-key-partition-list"))
    XCTAssertTrue(contents.contains("codesign --verify"))
  }

  func testInstalledControllerResolverRejectsEveryUnsafeInstallationState() throws {
    let contents = try String(
      contentsOf: repositoryRoot.appending(path: "bin/_rl-common.fish"),
      encoding: .utf8
    )

    XCTAssertTrue(contents.contains("not test -x $executable"), "missing executable")
    XCTAssertTrue(contents.contains("codesign --verify --strict $executable"), "invalid signature")
    XCTAssertTrue(
      contents.contains("The controller source changed after installation"), "stale source")
    XCTAssertTrue(
      contents.contains("$actual_requirement\" != \"$expected_requirement"), "requirement rotation")
    XCTAssertTrue(contents.contains("required fixed identifier"), "fixed identifier")
  }

  func testRequirementRotationIsRejectedBeforeKeychainAuthorization() throws {
    let contents = try String(
      contentsOf: repositoryRoot.appending(path: "bin/rl-install"),
      encoding: .utf8
    )
    let requirementCheck = try XCTUnwrap(contents.range(of: "The signing requirement changed"))
    let authorization = try XCTUnwrap(
      contents.range(of: "authorize-current-executable")
    )
    XCTAssertLessThan(requirementCheck.lowerBound, authorization.lowerBound)
  }

  func testAuthorizationMigrationIncludesTheExistingServerAuthorizationStoreWithoutReplacingIt()
    throws
  {
    let contents = try String(
      contentsOf: repositoryRoot.appending(
        path: "Sources/ControllerCLI/ControllerIdentityAccessAuthorizer.swift"
      ),
      encoding: .utf8
    )
    XCTAssertTrue(contents.contains("controller-server-authorization"))
    XCTAssertTrue(contents.contains("SecKeychainFindGenericPassword"))
    XCTAssertTrue(contents.contains("kSecACLAuthorizationDecrypt"))
    XCTAssertFalse(contents.contains("SecKeychainItemDelete"))
  }

  func testLearningAppDeclaresALaunchScreen() throws {
    let infoURL = repositoryRoot.appending(
      path: "Config/RemoteLocationLearning-Info.plist"
    )
    let data = try Data(contentsOf: infoURL)
    let value = try PropertyListSerialization.propertyList(from: data, format: nil)
    let info = try XCTUnwrap(value as? [String: Any])
    XCTAssertTrue(
      info["UILaunchScreen"] != nil || info["UILaunchStoryboardName"] != nil,
      "A launch screen is required to avoid iPhone compatibility letterboxing"
    )
  }
}
