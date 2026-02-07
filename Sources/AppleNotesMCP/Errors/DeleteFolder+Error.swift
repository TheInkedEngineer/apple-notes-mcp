import Foundation

extension Error {
  /// Validation and script-mapping errors for `delete_folder`.
  enum DeleteFolder: LocalizedError, Equatable {
    case missingFolder
    case missingConfirmCascadeDelete
    case invalidConfirmCascadeDeleteType
    case confirmCascadeDeleteMustBeTrue
    case cannotDeleteSystemFolder(String)
    case invalidScriptResponse

    var errorDescription: String? {
      switch self {
      case .missingFolder:
        return "Missing required parameter: 'folder'."
      case .missingConfirmCascadeDelete:
        return "Missing required parameter: 'confirmCascadeDelete'. Set it to true to acknowledge destructive deletion."
      case .invalidConfirmCascadeDeleteType:
        return "Invalid 'confirmCascadeDelete' value: expected a boolean true."
      case .confirmCascadeDeleteMustBeTrue:
        return "Invalid 'confirmCascadeDelete' value: must be true. delete_folder always performs cascading deletion."
      case let .cannotDeleteSystemFolder(name):
        return "Cannot delete system folder '\(name)'."
      case .invalidScriptResponse:
        return "Apple Notes returned an invalid response for delete_folder."
      }
    }
  }
}
