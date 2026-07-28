import Foundation

public struct ManualSimulationRequest: Codable, Equatable, Sendable {
  public let requestID: UUID
  public let location: SelectedLocation
  public let requestedAt: Date

  public init(requestID: UUID, location: SelectedLocation, requestedAt: Date) {
    self.requestID = requestID
    self.location = location
    self.requestedAt = requestedAt
  }
}

public enum ManualSimulationSessionError: Error, Equatable, Sendable {
  case noSelectedLocation
}

public enum ManualSimulationFailure: Equatable, Sendable {
  case responseIdentityMismatch
  case controllerUnavailable
  case requestRejected(stableCode: String)
}

public enum AppliedVerificationIssue: Equatable, Sendable {
  case notAfterRequest
  case timedOut(elapsedSeconds: TimeInterval)
  case tooFar(distanceMeters: Double)
}

public enum ManualSimulationStatus: Equatable, Sendable {
  case noSelection
  case selected(SelectedLocation)
  case applying(ManualSimulationRequest)
  case applied(ManualSimulationRequest)
  case appliedNotVerified(ManualSimulationRequest, AppliedVerificationIssue)
  case verified(ManualSimulationRequest, ObservationMatchEvidence)
  case failed(ManualSimulationRequest, ManualSimulationFailure)
  case stopped
}

public enum ManualSimulationStopStatus: Equatable, Sendable {
  case idle
  case stopping(requestID: UUID)
  case stopped(requestID: UUID)
  case failed(requestID: UUID, ManualSimulationFailure)
}

public struct ManualSimulationSession: Equatable, Sendable {
  public private(set) var selected: SelectedLocation?
  public private(set) var latestObservation: LocationObservation?
  public private(set) var activeAppliedRequest: ManualSimulationRequest?
  public private(set) var status: ManualSimulationStatus = .noSelection
  public private(set) var stopStatus: ManualSimulationStopStatus = .idle

  public init() {}

  public mutating func select(latitude: String, longitude: String) throws {
    select(
      try SelectedLocation.parse(
        latitude: latitude,
        longitude: longitude
      )
    )
  }

  public mutating func select(_ location: SelectedLocation) {
    selected = location
    status = .selected(location)
  }

  @discardableResult
  public mutating func beginApply(
    requestID: UUID,
    at date: Date
  ) throws -> ManualSimulationRequest {
    guard let selected else {
      throw ManualSimulationSessionError.noSelectedLocation
    }

    let request = ManualSimulationRequest(
      requestID: requestID,
      location: selected,
      requestedAt: date
    )
    stopStatus = .idle
    status = .applying(request)
    return request
  }

  @discardableResult
  public mutating func acknowledgeApplied(requestID: UUID) -> Bool {
    guard case .applying(let request) = status else {
      return false
    }
    guard request.requestID == requestID else {
      status = .failed(request, .responseIdentityMismatch)
      return false
    }

    activeAppliedRequest = request
    status = .applied(request)
    return true
  }

  @discardableResult
  public mutating func fail(
    requestID: UUID,
    reason: ManualSimulationFailure
  ) -> Bool {
    guard let request = currentRequest else {
      return false
    }
    guard request.requestID == requestID else {
      status = .failed(request, .responseIdentityMismatch)
      return false
    }

    status = .failed(request, reason)
    return true
  }

  public mutating func record(_ observation: LocationObservation) {
    latestObservation = observation

    let request: ManualSimulationRequest
    switch status {
    case .applied(let current), .appliedNotVerified(let current, _):
      request = current
    default:
      return
    }

    switch ObservationMatcher.evaluate(
      selected: request.location,
      requestedAt: request.requestedAt,
      observation: observation
    ) {
    case .matched(let evidence):
      status = .verified(request, evidence)
    case .notAfterRequest:
      status = .appliedNotVerified(request, .notAfterRequest)
    case .timedOut(let elapsedSeconds):
      status = .appliedNotVerified(
        request,
        .timedOut(elapsedSeconds: elapsedSeconds)
      )
    case .tooFar(let distanceMeters):
      status = .appliedNotVerified(
        request,
        .tooFar(distanceMeters: distanceMeters)
      )
    }
  }

  public mutating func expire(at date: Date) {
    let request: ManualSimulationRequest
    switch status {
    case .applied(let current), .appliedNotVerified(let current, _):
      request = current
    default:
      return
    }

    let elapsedSeconds = date.timeIntervalSince(request.requestedAt)
    guard elapsedSeconds > ObservationMatcher.maximumElapsedSeconds else {
      return
    }
    status = .appliedNotVerified(
      request,
      .timedOut(elapsedSeconds: elapsedSeconds)
    )
  }

  public mutating func beginStop(requestID: UUID) {
    stopStatus = .stopping(requestID: requestID)
  }

  @discardableResult
  public mutating func acknowledgeStopped(requestID: UUID) -> Bool {
    guard case .stopping(let expectedID) = stopStatus else {
      return false
    }
    guard expectedID == requestID else {
      stopStatus = .failed(
        requestID: expectedID,
        .responseIdentityMismatch
      )
      return false
    }

    activeAppliedRequest = nil
    stopStatus = .stopped(requestID: requestID)
    status = .stopped
    return true
  }

  @discardableResult
  public mutating func failStop(
    requestID: UUID,
    reason: ManualSimulationFailure
  ) -> Bool {
    guard case .stopping(let expectedID) = stopStatus else {
      return false
    }
    guard expectedID == requestID else {
      stopStatus = .failed(
        requestID: expectedID,
        .responseIdentityMismatch
      )
      return false
    }

    stopStatus = .failed(requestID: requestID, reason)
    return true
  }

  private var currentRequest: ManualSimulationRequest? {
    switch status {
    case .applying(let request),
      .applied(let request),
      .appliedNotVerified(let request, _),
      .verified(let request, _),
      .failed(let request, _):
      request
    case .noSelection, .selected, .stopped:
      nil
    }
  }
}
