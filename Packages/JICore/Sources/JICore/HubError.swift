/// Named cases are UI contracts (pinned food-log contract: 409 → YAZIO_DUPLICATE copy, 502 → YAZIO_AUTH_EXPIRED copy).
public enum HubError: Error, Equatable, Sendable {
    case unauthorized
    case duplicate(detail: String)
    case yazioAuthExpired(detail: String)
    case http(status: Int, detail: String?)
    case network(String)
    case decoding(String)

    public static func from(status: Int, detail: String?) -> HubError {
        switch status {
        case 401: return .unauthorized
        case 409: return .duplicate(detail: detail ?? "")
        case 502: return .yazioAuthExpired(detail: detail ?? "")
        default: return .http(status: status, detail: detail)
        }
    }
}
