import Foundation

enum ToolError: Error, LocalizedError {
    case invalidToolArgs(toolName: String, args: String, underlyingError: Error)
    case invalidArgsEncoding

    public var errorDescription: String? {
        switch self {
        case .invalidToolArgs(let toolName, _, let underlyingError):
            return
                "Invalid arguments for tool '\(toolName)': \(underlyingError.localizedDescription)"
        case .invalidArgsEncoding:
            return "Invalid arguments encoding"
        }
    }
}
