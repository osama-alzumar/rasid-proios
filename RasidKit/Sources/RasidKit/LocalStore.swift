import Foundation

/// An earn/redeem recorded on this device that the server has not confirmed yet.
public struct PendingOperation: Codable, Sendable, Hashable, Identifiable {
    public enum Status: String, Codable, Sendable {
        /// Waiting to be sent (or being retried after a network failure).
        case pending
        /// The server refused it; it no longer affects the balance and needs
        /// the cashier's attention.
        case rejected
    }

    public var id: UUID
    public var draft: TransactionDraft
    /// Balance change computed locally by RewardRules (always positive).
    public var pointsChange: Int
    public var memberName: String
    public var createdAt: Date
    public var status: Status
    public var lastError: String?
    public var attempts: Int

    public init(id: UUID = UUID(), draft: TransactionDraft, pointsChange: Int, memberName: String, createdAt: Date = Date(), status: Status = .pending, lastError: String? = nil, attempts: Int = 0) {
        self.id = id
        self.draft = draft
        self.pointsChange = pointsChange
        self.memberName = memberName
        self.createdAt = createdAt
        self.status = status
        self.lastError = lastError
        self.attempts = attempts
    }

    /// Signed effect on the member's balance while still pending.
    public var signedDelta: Int {
        guard status == .pending else { return 0 }
        return draft.type == .earn ? pointsChange : -pointsChange
    }
}

/// Everything the app keeps on the device for one logged-in user.
public struct Snapshot: Codable, Sendable, Equatable {
    public var user: User?
    public var shop: Shop?
    public var services: [Service] = []
    public var members: [Int: Member] = [:]
    public var recentTransactions: [ServerTransaction] = []
    public var pending: [PendingOperation] = []
    /// Server time of the last complete members download (cursor for deltas).
    public var membersSyncedAt: String?
    public var lastSuccessfulSync: Date?

    public init() {}

    /// Balance shown to the cashier: server balance plus pending local ops.
    public func displayBalance(memberId: Int) -> Int {
        (members[memberId]?.currentBalance ?? 0) + pendingDelta(memberId: memberId)
    }

    public func pendingDelta(memberId: Int) -> Int {
        pending.filter { $0.draft.memberId == memberId }.reduce(0) { $0 + $1.signedDelta }
    }

    public var pendingCount: Int { pending.filter { $0.status == .pending }.count }
    public var rejectedCount: Int { pending.filter { $0.status == .rejected }.count }
}

/// File-backed store for the offline copy. All mutations go through this actor
/// and are written atomically, so a crash never leaves a half-written file.
public actor LocalStore {
    public private(set) var snapshot: Snapshot
    private let fileURL: URL?

    /// - Parameter fileURL: nil keeps everything in memory (tests, previews).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = Snapshot()
        }
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Rasid", isDirectory: true).appendingPathComponent("store.json")
    }

    // MARK: Reads

    /// Balance shown to the cashier: server balance plus pending local ops.
    public func displayBalance(memberId: Int) -> Int {
        snapshot.displayBalance(memberId: memberId)
    }

    /// Exact match on the codes a wallet pass / cashier may present.
    public func findMember(code raw: String) -> Member? {
        let code = Self.normalize(raw)
        guard !code.isEmpty else { return nil }
        return snapshot.members.values.first { member in
            [member.externalId, member.phone, member.passkitId].compactMap { $0 }.contains { Self.normalize($0) == code }
        }
    }

    /// Name / phone / ID contains-search for the members list.
    public func searchMembers(_ query: String, limit: Int = 200) -> [Member] {
        let q = Self.normalize(query)
        let all = snapshot.members.values
        let matches: [Member]
        if q.isEmpty {
            matches = Array(all)
        } else {
            matches = all.filter { m in
                Self.normalize(m.name).contains(q)
                    || [m.phone, m.externalId].compactMap { $0 }.contains { Self.normalize($0).contains(q) }
                    || m.vehicles.contains { Self.normalize($0.plateText).contains(q) || Self.normalize($0.plateNumber ?? "").contains(q) }
            }
        }
        return Array(matches.sorted { ($0.createdAt ?? "", $0.id) > ($1.createdAt ?? "", $1.id) }.prefix(limit))
    }

    // MARK: Session

    public func replaceSession(user: User) throws {
        snapshot = Snapshot()
        snapshot.user = user
        try save()
    }

    public func clear() throws {
        snapshot = Snapshot()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    // MARK: Server data

    public func applyBootstrap(_ payload: BootstrapPayload) throws {
        snapshot.user = payload.user
        snapshot.shop = payload.shop
        snapshot.services = payload.services
        try save()
    }

    /// Applies one page of members. `fullIds` (first page only) removes
    /// members that no longer exist on the server.
    public func applyMembersPage(_ page: MembersPage) throws {
        if let ids = page.meta.allIds {
            let keep = Set(ids)
            snapshot.members = snapshot.members.filter { keep.contains($0.key) }
        }
        for member in page.data {
            snapshot.members[member.id] = member
        }
        try save()
    }

    public func finishMembersSync(serverTime: String, at date: Date = Date()) throws {
        snapshot.membersSyncedAt = serverTime
        snapshot.lastSuccessfulSync = date
        try save()
    }

    public func upsertMember(_ member: Member) throws {
        snapshot.members[member.id] = member
        try save()
    }

    public func addVehicle(_ vehicle: Vehicle) throws {
        guard var member = snapshot.members[vehicle.memberId] else { return }
        member.vehicles.removeAll { $0.id == vehicle.id }
        member.vehicles.append(vehicle)
        snapshot.members[member.id] = member
        try save()
    }

    public func setRecentTransactions(_ transactions: [ServerTransaction]) throws {
        snapshot.recentTransactions = transactions
        try save()
    }

    // MARK: Outbox

    /// Validates and queues an operation. The displayed balance changes
    /// immediately; the server is told on the next sync.
    @discardableResult
    public func enqueue(_ draft: TransactionDraft) throws -> PendingOperation {
        guard let shop = snapshot.shop else { throw RewardRuleError.countRequired }
        guard let member = snapshot.members[draft.memberId] else { throw APIError.rejected(status: 404, message: "العميل غير موجود على هذا الجهاز.") }
        let service = draft.serviceId.flatMap { id in snapshot.services.first { $0.id == id } }
        let balance = displayBalance(memberId: draft.memberId)
        switch RewardRules.evaluate(draft, shop: shop, balance: balance, service: service) {
        case .failure(let error):
            throw error
        case .success(let change):
            let op = PendingOperation(draft: draft, pointsChange: change, memberName: member.name)
            snapshot.pending.append(op)
            try save()
            return op
        }
    }

    public var pendingOperations: [PendingOperation] { snapshot.pending.filter { $0.status == .pending } }

    /// The server applied the operation: drop it from the outbox and adopt the
    /// server's balance for that member.
    public func confirm(_ id: UUID, with result: TransactionResult) throws {
        guard let index = snapshot.pending.firstIndex(where: { $0.id == id }) else { return }
        let op = snapshot.pending.remove(at: index)
        if let balance = result.transaction.memberBalanceAfter, var member = snapshot.members[op.draft.memberId] {
            member.currentBalance = balance
            if op.draft.type == .redeem { member.redeemCount += result.alreadyApplied ? 0 : 1 }
            snapshot.members[member.id] = member
        }
        var transaction = result.transaction
        if transaction.memberName == nil { transaction.memberName = op.memberName }
        snapshot.recentTransactions.removeAll { $0.id == transaction.id }
        snapshot.recentTransactions.insert(transaction, at: 0)
        if snapshot.recentTransactions.count > 300 { snapshot.recentTransactions.removeLast(snapshot.recentTransactions.count - 300) }
        try save()
    }

    public func markRejected(_ id: UUID, message: String) throws {
        guard let index = snapshot.pending.firstIndex(where: { $0.id == id }) else { return }
        snapshot.pending[index].status = .rejected
        snapshot.pending[index].lastError = message
        try save()
    }

    public func noteAttempt(_ id: UUID, error: String) throws {
        guard let index = snapshot.pending.firstIndex(where: { $0.id == id }) else { return }
        snapshot.pending[index].attempts += 1
        snapshot.pending[index].lastError = error
        try save()
    }

    public func discard(_ id: UUID) throws {
        snapshot.pending.removeAll { $0.id == id }
        try save()
    }

    // MARK: Persistence

    private func save() throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }

    /// Case/space-insensitive form with Arabic-Indic digits mapped to ASCII,
    /// so "٠٥٥..." matches "055...".
    static func normalize(_ string: String) -> String {
        let arabicIndic: [Character: Character] = ["٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4", "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
                                                   "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4", "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"]
        return String(string.lowercased().compactMap { ch -> Character? in
            if ch.isWhitespace { return nil }
            return arabicIndic[ch] ?? ch
        })
    }
}
