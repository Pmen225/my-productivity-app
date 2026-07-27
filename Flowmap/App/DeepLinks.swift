import Foundation

/// The destinations a notification tap, App Intent or URL can open.
public enum DeepLink: String, CaseIterable, Sendable {
    case today
    case focus
    case map
    case calendar
    case library
    case inbox
    case assistant

    public static let scheme = "flowmap"

    /// Menu-item and tab wording for this destination.
    public var title: String {
        switch self {
        case .today: "Today"
        case .focus: "Focus"
        case .map: "Map"
        case .calendar: "Calendar"
        case .library: "Library"
        case .inbox: "Inbox"
        case .assistant: "Assistant"
        }
    }

    public var url: URL? { URL(string: "\(Self.scheme)://\(rawValue)") }

    public init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        guard let host = url.host(), let link = DeepLink(rawValue: host) else { return nil }
        self = link
    }
}

/// A request to open something specific, carried from a notification payload.
public struct DeepLinkRequest: Equatable, Sendable {
    public let destination: DeepLink
    public let taskID: UUID?
    public let segmentID: UUID?

    public init(destination: DeepLink, taskID: UUID? = nil, segmentID: UUID? = nil) {
        self.destination = destination
        self.taskID = taskID
        self.segmentID = segmentID
    }

    /// Builds a request from a notification's `userInfo`.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let route = userInfo["route"] as? String,
              let destination = DeepLink(rawValue: route)
        else { return nil }
        self.destination = destination
        self.taskID = (userInfo["taskID"] as? String).flatMap(UUID.init(uuidString:))
        self.segmentID = (userInfo["segmentID"] as? String).flatMap(UUID.init(uuidString:))
    }
}
