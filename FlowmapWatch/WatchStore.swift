import Foundation
import Observation

/// Where the watch app and its complication agree on the truth.
public enum WatchSharedStore {
    /// Shared with the widget extension; the phone never writes here.
    public static let appGroup = "group.com.flowmap.app"
    private static let snapshotKey = "flowmap.watch.snapshot"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    public static func write(_ snapshot: WatchSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    public static func read() -> WatchSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }
}

/// The watch app's single source of state.
///
/// It owns the link to the phone, keeps the last snapshot for the complication,
/// and drives a one-second tick so the countdown moves without any message
/// traffic — the snapshot carries an end date, so time passes locally.
@MainActor
@Observable
public final class WatchStore {
    public let link = WatchSyncService()

    /// Advances once a second while a session is running, purely to redraw.
    public private(set) var now: Date = Date()

    private var timer: Timer?

    public init() {
        link.activate()
        startTicking()
    }

    public var snapshot: WatchSnapshot? {
        // Fall back to the last snapshot written for the complication so a cold
        // launch out of range shows the day rather than an empty screen.
        link.snapshot ?? WatchSharedStore.read()
    }

    /// Mirrors every new snapshot into the shared container for the complication.
    public func persistLatest() {
        guard let snapshot = link.snapshot else { return }
        WatchSharedStore.write(snapshot)
    }

    public func send(_ command: WatchCommand) {
        link.send(command)
    }

    private func startTicking() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.persistLatest()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
