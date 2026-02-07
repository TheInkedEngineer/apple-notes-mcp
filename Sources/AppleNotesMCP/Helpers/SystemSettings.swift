import Foundation

/// Permission contract used by tool registry before tool execution.
protocol PermissionChecking: Sendable {
  @MainActor
  func ensurePermission() throws(Error.SystemSettings)
}

/// Production permission checker that delegates to system Apple Events APIs.
struct SystemPermissionChecker: PermissionChecking {
  @MainActor
  func ensurePermission() throws(Error.SystemSettings) {
    try SystemSettings.ensureAutomationPermission()
  }
}

/// System integration for Apple Notes automation permission checks.
@MainActor
enum SystemSettings {
  private static let notesBundleID = "com.apple.Notes"

  /// Ensures the current process can automate Apple Notes.
  ///
  /// This may trigger a system prompt on first access.
  static func ensureAutomationPermission() throws(Error.SystemSettings) {
    var targetDesc = AEAddressDesc()
    let createStatus = notesBundleID.withCString { cString in
      AECreateDesc(DescType(typeApplicationBundleID), cString, strlen(cString), &targetDesc)
    }

    defer {
      AEDisposeDesc(&targetDesc)
    }

    guard createStatus == noErr else {
      throw .invalidAutomationTarget(status: createStatus)
    }

    let status = AEDeterminePermissionToAutomateTarget(
      &targetDesc,
      typeWildCard,
      typeWildCard,
      true
    )

    switch status {
    // `procNotFound`: API missing at runtime (older macOS), treat as no-op.
    case noErr, OSStatus(procNotFound):
      return
    case -1744: // errAEEventWouldRequireUserConsent
      throw Error.SystemSettings.missingUserConsent
    case -1743: // errAEEventNotPermitted
      throw Error.SystemSettings.consentNotGranted
    default:
      throw Error.SystemSettings.failedToCheckPermission(status: status)
    }
  }
}
