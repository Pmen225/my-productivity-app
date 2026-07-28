#if os(iOS) || os(watchOS)
import Foundation
import WatchConnectivity

/// The phone/watch link, and nothing else.
///
/// It moves two payload types and holds no opinion about either: the owner
/// supplies a snapshot when asked and handles commands when they arrive. Both
/// sides use this same class — on the phone it publishes and receives commands,
/// on the watch it receives and sends. Keeping one implementation means the two
/// halves cannot drift apart in how they encode a message.
@MainActor
@Observable
public final class WatchSyncService: NSObject {

    /// Latest snapshot received from the phone. Only the watch reads this.
    public private(set) var snapshot: WatchSnapshot?

    /// True once the counterpart app is installed and the session is active.
    public private(set) var isLinked: Bool = false

    /// Called on the phone when the watch sends a command.
    public var commandHandler: ((WatchCommand) -> Void)?

    /// Called on the phone whenever a fresh snapshot is needed.
    public var snapshotProvider: (() -> WatchSnapshot)?

    private var session: WCSession?
    private var lastPushed: WatchSnapshot?

    public override init() {
        super.init()
    }

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    // MARK: - Phone side

    /// Publishes a snapshot if it differs from the last one sent.
    ///
    /// Application context rather than a message: it survives the watch being
    /// asleep or out of range, and only the most recent one is ever delivered,
    /// which is exactly the semantics a "what is running now" payload wants.
    public func push(_ snapshot: WatchSnapshot, force: Bool = false) {
        guard let session, session.activationState == .activated else { return }
        if !force, let lastPushed, lastPushed.isEquivalent(to: snapshot) { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        lastPushed = snapshot
        try? session.updateApplicationContext([WatchSyncKey.snapshot: data])
    }

    /// Recomputes and publishes. Safe to call often — `push` filters no-ops.
    public func publishCurrent(force: Bool = false) {
        guard let snapshotProvider else { return }
        push(snapshotProvider(), force: force)
    }

    // MARK: - Watch side

    public func send(_ command: WatchCommand) {
        guard let session, let data = try? JSONEncoder().encode(command) else { return }
        let payload: [String: Any] = [WatchSyncKey.command: data]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in })
        } else {
            // The phone picks it up on next launch rather than the tap being lost.
            session.transferUserInfo(payload)
        }
    }

    // MARK: - Delivery

    private func ingest(_ payload: [String: Any]) {
        if let data = payload[WatchSyncKey.snapshot] as? Data,
           let decoded = try? JSONDecoder().decode(WatchSnapshot.self, from: data) {
            snapshot = decoded
        }
        if let data = payload[WatchSyncKey.command] as? Data,
           let command = try? JSONDecoder().decode(WatchCommand.self, from: data) {
            if case .requestSnapshot = command {
                publishCurrent(force: true)
            } else {
                commandHandler?(command)
                publishCurrent(force: true)
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSyncService: WCSessionDelegate {
    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let linked: Bool
        #if os(iOS)
        linked = activationState == .activated && session.isPaired && session.isWatchAppInstalled
        #else
        linked = activationState == .activated
        #endif
        // Narrowed to `Data` here rather than at the far end: the raw dictionary
        // is not Sendable and cannot cross to the main actor.
        let context = session.receivedApplicationContext.compactMapValues { $0 as? Data }
        Task { @MainActor in
            self.isLinked = linked
            if !context.isEmpty { self.ingest(context) }
            #if os(watchOS)
            self.send(.requestSnapshot)
            #else
            self.publishCurrent(force: true)
            #endif
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        let copy = message.compactMapValues { $0 as? Data }
        Task { @MainActor in self.ingest(copy) }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let copy = applicationContext.compactMapValues { $0 as? Data }
        Task { @MainActor in self.ingest(copy) }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        let copy = userInfo.compactMapValues { $0 as? Data }
        Task { @MainActor in self.ingest(copy) }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate so a switched watch keeps receiving snapshots.
        WCSession.default.activate()
    }
    #endif
}

// MARK: - Change detection

extension WatchSnapshot {
    /// Equality that ignores `generatedAt`, so a re-render does not cost a transfer.
    func isEquivalent(to other: WatchSnapshot) -> Bool {
        var lhs = self
        var rhs = other
        lhs.generatedAt = .distantPast
        rhs.generatedAt = .distantPast
        return lhs == rhs
    }
}
#endif
