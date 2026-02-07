import Foundation

extension Error {
  /// Validation/runtime errors for `create_folder`.
  enum CreateFolder: LocalizedError, Equatable {
    case missingFolder
    case invalidScriptResponse

    var errorDescription: String? {
      switch self {
      case .missingFolder:
        return "Missing required parameter: 'folder'."
      case .invalidScriptResponse:
        return "Apple Notes returned an invalid response for create_folder."
      }
    }
  }
}
