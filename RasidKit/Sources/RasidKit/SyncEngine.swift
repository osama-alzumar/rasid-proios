import Foundation

public struct SyncReport: Equatable, Sendable {
    public var sent = 0
    public var rejected = 0
    public var membersUpdated = 0
    /// Set when the server could not be reached; local data stays usable.
    public var offline = false

    public init() {}
}

/// Pushes the outbox, then pulls what changed on the server.
///
/// Ordering matters: the outbox is flushed first and the pull is skipped if
/// any send failed transiently. Otherwise a send whose response was lost
/// could be counted twice (once in the pulled server balance, once as still
/// pending) until the retry comes back as `already_applied`.
public struct SyncEngine: Sendable {
    public let store: LocalStore
    public let api: APIClient

    public init(store: LocalStore, api: APIClient) {
        self.store = store
        self.api = api
    }

    public func sync(includeTransactions: Bool = true) async throws -> SyncReport {
        var report = SyncReport()

        let flushed = try await flushOutbox(into: &report)
        guard flushed else {
            report.offline = true
            return report
        }

        do {
            try await store.applyBootstrap(api.bootstrap())
            report.membersUpdated = try await pullMembers()
            if includeTransactions {
                try await store.setRecentTransactions(api.recentTransactions())
            }
        } catch let error as APIError where error.isTransient {
            report.offline = true
        }
        return report
    }

    /// - Returns: false if it stopped early because the server was unreachable.
    func flushOutbox(into report: inout SyncReport) async throws -> Bool {
        for op in await store.pendingOperations {
            do {
                let result = try await api.createTransaction(op.draft, clientUUID: op.id)
                try await store.confirm(op.id, with: result)
                report.sent += 1
            } catch let error as APIError {
                switch error {
                case .offline, .server:
                    try await store.noteAttempt(op.id, error: error.message)
                    return false
                case .unauthorized, .shopExpired, .accountDisabled:
                    // Session-level problem: keep the operation queued and let
                    // the app handle the error (it is not this op's fault).
                    throw error
                case .rejected(_, let message):
                    try await store.markRejected(op.id, message: message)
                    report.rejected += 1
                }
            }
        }
        return true
    }

    /// Downloads members changed since the last sync (everything the first time).
    func pullMembers() async throws -> Int {
        let since = await store.snapshot.membersSyncedAt
        var afterId = 0
        var updated = 0
        var serverTime: String?
        while true {
            let page = try await api.members(since: since, afterId: afterId)
            if serverTime == nil { serverTime = page.meta.serverTime }
            try await store.applyMembersPage(page)
            updated += page.data.count
            guard page.meta.hasMore, let next = page.meta.nextAfterId else { break }
            afterId = next
        }
        // Use the time of the FIRST page as the next cursor, so anything that
        // changed while later pages were downloading is fetched again next time.
        if let serverTime { try await store.finishMembersSync(serverTime: serverTime) }
        return updated
    }
}
