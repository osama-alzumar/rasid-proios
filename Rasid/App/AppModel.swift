import Foundation
import Network
import RasidKit
import SwiftUI

/// App-wide state: session, the offline snapshot and background sync.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case loggedOut
        case loggedIn
    }

    @Published private(set) var phase: Phase
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var isOnline = true
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncError: String?
    /// Shown full-screen: the shop subscription ended or the account was disabled.
    @Published var blockingMessage: String?
    /// The platform owner's session is locked behind Face ID / the device
    /// passcode whenever the app comes back to the foreground.
    @Published private(set) var isLocked = false
    /// Platform announcements waiting to be shown, first one on screen.
    @Published private(set) var systemMessages: [SystemMessage] = []
    private var fetchedSystemMessages = false

    private var store: LocalStore
    private var api: APIClient
    private let monitor = NWPathMonitor()
    private var timer: Timer?
    private var syncTask: Task<Void, Never>?
    let isDemo: Bool

    static func make() -> AppModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-RasidDemo") {
            return AppModel(demo: true)
        }
        #endif
        return AppModel(demo: false)
    }

    private init(demo: Bool) {
        isDemo = demo
        // The Keychain survives uninstalling the app; a fresh install must not
        // silently reuse a session from a previous one.
        let installedKey = "hasLaunchedBefore"
        if !UserDefaults.standard.bool(forKey: installedKey) {
            Keychain.deleteToken()
            UserDefaults.standard.set(true, forKey: installedKey)
        }

        let token = demo ? nil : Keychain.loadToken()
        api = APIClient(token: token)
        store = LocalStore(fileURL: demo ? nil : LocalStore.defaultFileURL())
        phase = (token != nil || demo) ? .loggedIn : .loggedOut
        // Lock straight away on launch if the saved session is the owner's;
        // the snapshot is not loaded yet, so use the flag saved at login.
        isLocked = phase == .loggedIn && !demo && UserDefaults.standard.bool(forKey: Self.ownerSessionKey)

        if demo {
            Task {
                await loadDemo()
                await fetchSystemMessages()
            }
        } else {
            Task { await reloadSnapshot() }
            startMonitoring()
            if phase == .loggedIn {
                syncSoon()
                fetchSystemMessagesIfNeeded()
            }
        }
    }

    // MARK: Derived

    var user: User? { snapshot.user }
    var shop: Shop? { snapshot.shop }

    func balance(of member: Member) -> Int { snapshot.displayBalance(memberId: member.id) }

    func member(id: Int) -> Member? { snapshot.members[id] }

    /// Super admin without a chosen shop: only the platform tab makes sense.
    var needsShopSelection: Bool { user?.isSuperAdmin == true && snapshot.selectedShopId == nil }

    /// `shop_id` for requests that create things: the chosen shop for a super
    /// admin; staff never send one (the server pins them to their own shop).
    private var workingShopId: Int? { user?.isSuperAdmin == true ? snapshot.selectedShopId : nil }

    // MARK: Session

    func login(email: String, password: String) async throws {
        let result = try await APIClient().login(email: email.trimmingCharacters(in: .whitespaces), password: password)
        guard [.cashier, .shopManager, .superAdmin].contains(result.user.role) else {
            throw APIError.rejected(status: 403, message: "هذا التطبيق مخصص لحسابات التاجر والكاشير ومدير النظام.")
        }
        Keychain.saveToken(result.token)
        UserDefaults.standard.set(result.user.isSuperAdmin, forKey: Self.ownerSessionKey)
        api = APIClient(token: result.token)
        try await store.replaceSession(user: result.user)
        await reloadSnapshot()
        phase = .loggedIn
        await syncNow()
        await fetchSystemMessages()
    }

    func logout() async {
        if !isDemo { try? await api.logout() }
        Keychain.deleteToken()
        UserDefaults.standard.removeObject(forKey: Self.ownerSessionKey)
        isLocked = false
        api = APIClient()
        try? await store.clear()
        await reloadSnapshot()
        blockingMessage = nil
        lastSyncError = nil
        systemMessages = []
        fetchedSystemMessages = false
        phase = .loggedOut
    }

    // MARK: System messages

    /// Like the website, announcements are fetched at login — and, since the
    /// app keeps the user signed in, once each time the app is launched.
    func fetchSystemMessagesIfNeeded() {
        guard !fetchedSystemMessages, phase == .loggedIn else { return }
        Task { await fetchSystemMessages() }
    }

    private func fetchSystemMessages() async {
        if isDemo {
            if ProcessInfo.processInfo.arguments.contains("-RasidSystemMessage") {
                systemMessages = [SystemMessage(id: 1, title: "تحديث مهم", body: "أضفنا ميزة رسالة للعملاء: أرسل عروضك لعملائك فتصلهم إشعاراً على بطاقة المحفظة.", tone: .success, isForced: true)]
            }
            return
        }
        do {
            systemMessages = try await api.pendingSystemMessages()
            fetchedSystemMessages = true
        } catch {
            // Retried on the next launch; announcements never block the app.
        }
    }

    /// "فهمت": recorded on the server so display rules (once / first login) hold.
    func acknowledgeSystemMessage(_ message: SystemMessage) {
        systemMessages.removeAll { $0.id == message.id }
        guard !isDemo else { return }
        Task { try? await api.acknowledgeSystemMessage(id: message.id) }
    }

    /// Closed without confirming (only allowed when the message is not forced).
    func dismissSystemMessage(_ message: SystemMessage) {
        systemMessages.removeAll { $0.id == message.id }
    }

    // MARK: Owner lock

    static let ownerSessionKey = "ownerSession"

    var requiresDeviceLock: Bool { UserDefaults.standard.bool(forKey: Self.ownerSessionKey) && !isDemo }

    func lockIfNeeded() {
        if phase == .loggedIn && requiresDeviceLock { isLocked = true }
    }

    func unlock() async -> String? {
        switch await DeviceAuth.authenticate(reason: "افتح حساب صاحب المنصة") {
        case .success:
            isLocked = false
            syncSoon()
            return nil
        case .failure(let message):
            return message
        }
    }

    // MARK: Sync

    func syncSoon() {
        guard phase == .loggedIn, !isDemo else { return }
        syncTask?.cancel()
        syncTask = Task { await syncNow() }
    }

    func syncNow() async {
        guard phase == .loggedIn, !isDemo, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let report = try await SyncEngine(store: store, api: api).sync()
            lastSyncError = report.offline ? APIError.offline.message : nil
            if !report.offline { blockingMessage = nil }
        } catch let error as APIError {
            handleSessionError(error)
        } catch {
            lastSyncError = error.localizedDescription
        }
        await reloadSnapshot()
    }

    private func handleSessionError(_ error: APIError) {
        switch error {
        case .unauthorized:
            Task { await logout() }
        case .shopExpired(let message), .accountDisabled(let message):
            blockingMessage = message
        default:
            lastSyncError = error.message
        }
    }

    private func reloadSnapshot() async {
        snapshot = await store.snapshot
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let cameBack = online && !self.isOnline
                self.isOnline = online
                if cameBack { self.syncSoon() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "rasid.network"))
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncSoon() }
        }
    }

    // MARK: Cashier actions

    /// Local copy first (works offline), then the server, which can also pull
    /// a member from PassKit on first scan.
    func findMember(code: String) async throws -> Member {
        if let local = await store.findMember(code: code) { return local }
        guard !isDemo else { throw APIError.rejected(status: 404, message: "لم يتم العثور على العميل.") }
        do {
            let member = try await api.lookupMember(code: code.trimmingCharacters(in: .whitespacesAndNewlines))
            // A super admin's lookup searches every shop; only accept the shop being worked on.
            if let shopId = workingShopId, member.shopId != shopId {
                throw APIError.rejected(status: 404, message: "هذا العميل مسجل في محل آخر.")
            }
            try await store.upsertMember(member)
            await reloadSnapshot()
            return member
        } catch APIError.rejected(404, _) {
            throw APIError.rejected(status: 404, message: "لم يتم العثور على عميل بهذا الرمز.")
        }
    }

    func searchMembers(_ query: String) async -> [Member] {
        await store.searchMembers(query)
    }

    /// Records the operation on the device immediately, then tries to send it.
    @discardableResult
    func record(_ draft: TransactionDraft) async throws -> PendingOperation {
        let op = try await store.enqueue(draft)
        await reloadSnapshot()
        syncSoon()
        return op
    }

    func discard(_ op: PendingOperation) async {
        try? await store.discard(op.id)
        await reloadSnapshot()
    }

    func createMember(name: String, phone: String?) async throws -> Member {
        let member = try await api.createMember(name: name, phone: phone, shopId: workingShopId)
        try await store.upsertMember(member)
        await reloadSnapshot()
        return member
    }

    func createVehicle(memberId: Int, lettersAr: String, number: String, make: String?, model: String?, color: String?) async throws {
        let vehicle = try await api.createVehicle(memberId: memberId, lettersAr: lettersAr, number: number, make: make, model: model, color: color)
        try await store.addVehicle(vehicle)
        await reloadSnapshot()
    }

    func dashboard(period: String) async throws -> DashboardStats {
        try await api.dashboardStats(period: period)
    }

    // MARK: Store messages

    /// Shop managers message their own shop's customers; the platform owner
    /// any shop they are working on. Cashiers cannot (server enforces it too).
    var canMessageCustomers: Bool {
        guard let user, shop != nil else { return false }
        return user.isManager || (user.isSuperAdmin && snapshot.selectedShopId != nil)
    }

    /// Sends the message to every customer's Wallet card (online only).
    func sendStoreMessage(_ message: String) async throws -> WalletReach? {
        guard let shop else { throw APIError.rejected(status: 400, message: "لا يوجد محل محدد.") }
        let reach = try await api.sendStoreMessage(shopId: shop.id, message: message)
        await syncNow()
        return reach
    }

    // MARK: Super admin

    func platformStats(period: String) async throws -> PlatformStats {
        try await api.platformStats(period: period)
    }

    func shops(search: String) async throws -> [Shop] {
        try await api.shops(search: search)
    }

    /// Switches the offline copy to another shop and downloads it.
    func selectShop(_ shop: Shop) async throws {
        try await store.selectShop(shop)
        await reloadSnapshot()
        await syncNow()
    }

    // MARK: Demo (screenshots / UI tests only)

    private func loadDemo() async {
        let user = User(id: 1, name: "أحمد الكاشير", email: "cashier@demo.rasid.pro", shopId: 1, vehicleModuleEnabled: true, role: ProcessInfo.processInfo.arguments.contains("-RasidManager") ? .shopManager : .cashier,
                        permissions: ["members.view-any", "members.view", "members.create", "transactions.view-any", "transactions.create", "vehicles.create"])
        var shop = Shop(id: 1, name: "مغسلة اللمعة", rewardType: .stamps, numberOfStamps: 6, pointsPerAmount: 1, vehicleModuleEnabled: true)
        shop.storeMessage = "الغسلة السابعة مجاناً"
        try? await store.replaceSession(user: user)
        let page = MembersPage(data: [
            Member(id: 1, shopId: 1, name: "سارة العتيبي", phone: "0551112222", externalId: "EXT_104233", currentBalance: 4,
                   vehicles: [Vehicle(id: 1, memberId: 1, plateLettersAr: "أ ب ج", plateNumber: "1234", make: "تويوتا", model: "كامري", color: "أبيض")]),
            Member(id: 2, shopId: 1, name: "خالد الشهري", phone: "0553334444", externalId: "EXT_582910", currentBalance: 6),
            Member(id: 3, shopId: 1, name: "منى القحطاني", phone: "0555556666", externalId: "EXT_771205", currentBalance: 1),
            Member(id: 4, shopId: 1, name: "فهد الدوسري", phone: "0557778888", externalId: "EXT_330418", currentBalance: 3),
        ], meta: .init(serverTime: "", hasMore: false, nextAfterId: nil, allIds: nil))
        try? await store.applyMembersPage(page)
        try? await store.applyBootstrap(BootstrapPayload(serverTime: "", user: user, shop: shop,
                                                         services: [Service(id: 1, name: "غسيل خارجي", price: 25), Service(id: 2, name: "غسيل شامل", price: 45)]))
        try? await store.setRecentTransactions([
            ServerTransaction(id: 3, memberId: 2, memberName: "خالد الشهري", pointsChange: 1, type: .earn, serviceName: "غسيل شامل", createdBy: "أحمد", createdAt: "2026-10-13 11:42:00"),
            ServerTransaction(id: 2, memberId: 1, memberName: "سارة العتيبي", pointsChange: 1, type: .earn, serviceName: "غسيل خارجي", createdBy: "أحمد", createdAt: "2026-10-13 10:15:00"),
            ServerTransaction(id: 1, memberId: 3, memberName: "منى القحطاني", pointsChange: 6, type: .redeem, createdBy: "أحمد", createdAt: "2026-10-12 18:03:00"),
        ])
        try? await store.finishMembersSync(serverTime: "")
        await reloadSnapshot()
    }
}
