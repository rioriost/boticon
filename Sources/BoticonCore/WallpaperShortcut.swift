import Foundation

public enum WallpaperShortcut {
    public static let defaultName = "Boticon壁紙を変更"

    public enum Outcome: Equatable {
        case success
        case cancelled
        case failure(String?)
    }

    public static func runURL(named name: String, requestID: UUID) -> URL? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)] + ["success", "cancel", "error"].map { result in
            var callback = URLComponents()
            callback.scheme = "boticon"
            callback.host = "shortcut"
            callback.path = "/\(result)"
            callback.queryItems = [URLQueryItem(name: "request", value: requestID.uuidString)]
            return URLQueryItem(name: "x-\(result)", value: callback.url!.absoluteString)
        }
        return components.url
    }

    public static func outcome(from url: URL, requestID: UUID) -> Outcome? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "boticon", parts.host == "shortcut",
              parts.user == nil, parts.password == nil, parts.port == nil,
              let requests = parts.queryItems?.filter({ $0.name == "request" }),
              requests.count == 1, requests[0].value == requestID.uuidString else { return nil }
        switch parts.path {
        case "/success": return .success
        case "/cancel": return .cancelled
        case "/error":
            return .failure(parts.queryItems?.first { $0.name == "errorMessage" }?.value)
        default: return nil
        }
    }
}
