import Foundation
import Observation

/// Visible but unobtrusive sync state. Errors surface; healthy sync stays quiet.
@Observable
@MainActor
public final class CloudSyncStatus {
    public enum State: Equatable, Sendable {
        case unknown
        case syncing
        case upToDate(Date)
        case unavailable(String)
        case failed(String)

        public var isProblem: Bool {
            switch self {
            case .unavailable, .failed: true
            case .unknown, .syncing, .upToDate: false
            }
        }
    }

    public static let shared = CloudSyncStatus()

    public private(set) var state: State = .unknown
    public private(set) var lastSuccessfulSync: Date?

    private init() {}

    public func report(_ newState: State) {
        state = newState
        if case .upToDate(let date) = newState {
            lastSuccessfulSync = date
        }
    }

    /// Called off the main actor by container setup before the app is running.
    nonisolated public func reportFromAnyThread(_ newState: State) {
        Task { @MainActor in self.report(newState) }
    }

    public var shortDescription: String {
        switch state {
        case .unknown: "Not checked yet"
        case .syncing: "Syncing…"
        case .upToDate(let date): "Synced \(DurationFormatter.time(date))"
        case .unavailable(let message): message
        case .failed(let message): message
        }
    }

    public var symbolName: String {
        switch state {
        case .unknown: "icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .upToDate: "checkmark.icloud"
        case .unavailable: "icloud.slash"
        case .failed: "exclamationmark.icloud"
        }
    }
}
