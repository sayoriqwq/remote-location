import CryptoKit
import Foundation
import Security

public enum ControllerIdentityError: Error, Equatable, Sendable {
  case invalidFingerprint
  case missingLeafCertificate
}

public struct ControllerIdentity: Codable, Hashable, Sendable {
  public let fingerprint: Data

  public init(fingerprint: Data) throws {
    guard fingerprint.count == 32 else {
      throw ControllerIdentityError.invalidFingerprint
    }
    self.fingerprint = fingerprint
  }

  public init(certificateDER: Data) throws {
    try self.init(fingerprint: Data(SHA256.hash(data: certificateDER)))
  }
}

public enum PairingCodeError: Error, Equatable, Sendable {
  case invalidFormat
  case incorrect
  case identityMismatch
  case expired
  case alreadyUsed
  case tooManyAttempts
}

public enum PairingCodeGenerationError: Error, Equatable, Sendable {
  case randomGenerationFailed(OSStatus)
}

public enum PairingCodeGenerator {
  public static func generate() throws -> String {
    let range = UInt32(1_000_000)
    let acceptedUpperBound = UInt32.max - (UInt32.max % range)
    while true {
      var random = UInt32.zero
      let status = withUnsafeMutableBytes(of: &random) { buffer in
        SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
      }
      guard status == errSecSuccess else {
        throw PairingCodeGenerationError.randomGenerationFailed(status)
      }
      guard random < acceptedUpperBound else {
        continue
      }
      return String(format: "%06u", random % range)
    }
  }
}

public enum PairingRedemption: Equatable, Sendable {
  case paired(ControllerIdentity)
}

public actor PairingCodeAuthority {
  private let codeBytes: [UInt8]
  private let identity: ControllerIdentity
  private let expiresAt: Date
  private let maximumFailedAttempts: Int
  private var failedAttempts = 0
  private var isUsed = false

  public init(
    code: String,
    identity: ControllerIdentity,
    expiresAt: Date,
    maximumFailedAttempts: Int = 5
  ) throws {
    let bytes = Array(code.utf8)
    guard bytes.count == 6, bytes.allSatisfy({ (48...57).contains($0) }) else {
      throw PairingCodeError.invalidFormat
    }
    guard maximumFailedAttempts > 0 else {
      throw PairingCodeError.tooManyAttempts
    }

    codeBytes = bytes
    self.identity = identity
    self.expiresAt = expiresAt
    self.maximumFailedAttempts = maximumFailedAttempts
  }

  public func redeem(
    code: String,
    presentedIdentity: ControllerIdentity,
    at date: Date
  ) throws -> PairingRedemption {
    guard !isUsed else {
      throw PairingCodeError.alreadyUsed
    }
    guard date <= expiresAt else {
      throw PairingCodeError.expired
    }
    guard failedAttempts < maximumFailedAttempts else {
      throw PairingCodeError.tooManyAttempts
    }
    guard presentedIdentity == identity else {
      failedAttempts += 1
      throw PairingCodeError.identityMismatch
    }
    guard constantTimeMatches(code) else {
      failedAttempts += 1
      throw PairingCodeError.incorrect
    }

    isUsed = true
    return .paired(identity)
  }

  private func constantTimeMatches(_ candidate: String) -> Bool {
    let candidateBytes = Array(candidate.utf8)
    var difference = UInt8(truncatingIfNeeded: candidateBytes.count ^ codeBytes.count)
    for index in codeBytes.indices {
      let candidateByte = index < candidateBytes.count ? candidateBytes[index] : 0
      difference |= codeBytes[index] ^ candidateByte
    }
    return difference == 0
  }
}
