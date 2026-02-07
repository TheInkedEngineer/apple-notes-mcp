import Foundation

extension Error {
  /// Errors emitted while checking macOS automation permissions.
  enum SystemSettings: LocalizedError {
    case consentNotGranted
    case failedToCheckPermission(status: OSStatus)
    case invalidAutomationTarget(status: OSErr)
    case missingUserConsent

    var errorDescription: String? {
      switch self {
      case .consentNotGranted:
        return Self.automationDeniedMessage(denied: true)
      case let .failedToCheckPermission(status):
        return "Failed to check permission to access system settings (status: \(status))."
      case let .invalidAutomationTarget(status):
        return """
        The system could not identify Apple Notes as an automation target.
        This usually indicates a configuration or installation issue (status: \(status)).
        """
      case .missingUserConsent:
        return Self.automationDeniedMessage(denied: false)
      }
    }

    private static func automationDeniedMessage(denied: Bool) -> String {
      let header = denied
      ? "Automation permission for Apple Notes was denied."
      : "Automation permission for Apple Notes has not been granted yet."

      return """
        \(header)

        Open System Settings > Privacy & Security > Automation, then enable your terminal (or Claude Code) to control Notes. After granting permission, run the tool again.
        """
    }
  }
}
