import Foundation
import XCTest
@testable import RasidKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Fake server

/// In-memory stand-in for the Laravel API, implementing the same rules as
/// TransactionController (incl. client_uuid idempotency) so the sync engine is
/// exercised end to end without a network.
final class FakeServer: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    var shop: Shop
    var members: [Int: Member]
    var memberUpdatedAt: [Int: Int] = [:]
    var clock = 1000
    var transactions: [(uuid: String?, tx: ServerTransaction)] = []
    var online = true
    /// Apply the next transaction but pretend the response was lost.
    var dropNextResponse = false
    var requests: [String] = []
    var expiredShop = false
    var role = "cashier"
    var storeMessage: String?
    /// shop_id query values received on app/* endpoints.
    var shopIdsSeen: [String?] = []

    init(shop: Shop, members: [Member]) {
        self.shop = shop
        self.members = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        for m in members { memberUpdatedAt[m.id] = clock }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try lock.withLock { try handle(request) }
    }

    private func handle(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        guard online else { throw URLError(.notConnectedToInternet) }
        let url = request.url!
        let path = url.path.replacingOccurrences(of: "/backend/api/", with: "")
        requests.append("\(request.httpMethod!) \(path)")
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        if expiredShop {
            return respond(403, ["success": false, "shop_expired": true, "message": "انتهى اشتراك المحل"])
        }
        if request.value(forHTTPHeaderField: "Authorization") != "Bearer good-token" && path != "login" {
            return respond(401, ["message": "Unauthenticated."])
        }

        if path.hasPrefix("app/") { shopIdsSeen.append(query["shop_id"]) }
        if role == "super_admin" && path.hasPrefix("app/") && path != "app/bootstrap" && query["shop_id"] == nil {
            return respond(422, ["message": "The shop id field is required."])
        }

        switch (request.httpMethod!, path) {
        case ("POST", "login"):
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            guard body["password"] as? String == "secret" else {
                return respond(401, ["success": false, "message": "بيانات الدخول غير صحيحة"])
            }
            return respond(200, ["success": true, "data": ["user": userJSON, "token": "good-token"]])
        case ("GET", "app/bootstrap"):
            let noShop = role == "super_admin" && query["shop_id"] == nil
            return respond(200, ["success": true, "data": [
                "server_time": "t\(clock)", "user": userJSON, "shop": noShop ? NSNull() : shopJSON as Any,
                "services": [["id": 7, "name": "غسيل", "price": "25.00", "is_active": true, "sort_order": 1]],
                "wallet_reach": noShop ? NSNull() : ["cards": "3", "devices": 5] as Any,
            ]])
        case ("GET", "app/members"):
            let since = query["since"].flatMap { Int($0.dropFirst()) }
            let afterId = Int(query["after_id"] ?? "0") ?? 0
            let pageSize = 2
            let filtered = members.values.filter { $0.id > afterId && (since == nil || memberUpdatedAt[$0.id]! > since!) }.sorted { $0.id < $1.id }
            let page = Array(filtered.prefix(pageSize))
            let hasMore = filtered.count > pageSize
            return respond(200, ["success": true, "data": page.map(memberJSON), "meta": [
                "server_time": "t\(clock)", "has_more": hasMore,
                "next_after_id": hasMore ? page.last!.id as Any : NSNull(),
                "all_ids": afterId == 0 ? members.keys.sorted() as Any : NSNull(),
            ]])
        case ("POST", "shops/\(shop.id)/push-message"):
            guard role != "cashier" else { return respond(403, ["message": "لا تملك صلاحية إرسال رسائل لعملاء هذا المحل."]) }
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            guard let message = body["message"] as? String, !message.isEmpty else {
                return respond(422, ["message": "The given data was invalid.", "errors": ["message": ["الرسالة مطلوبة."]]])
            }
            storeMessage = message
            return respond(200, ["success": true, "message": "تمت عملية الجدولة", "reach": ["cards": 3, "devices": 5]])
        case ("GET", "app/transactions"):
            return respond(200, ["success": true, "data": transactions.reversed().map { txJSON($0.tx) }])
        case ("POST", "transactions"):
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let uuid = body["client_uuid"] as? String
            if let uuid, let existing = transactions.first(where: { $0.uuid == uuid }) {
                return respond(200, ["success": true, "already_applied": true, "data": txJSON(existing.tx)])
            }
            let memberId = body["member_id"] as! Int
            guard var member = members[memberId] else { return respond(422, ["message": "The selected member id is invalid."]) }
            let type = TransactionType(rawValue: body["type"] as! String)!
            let draft = TransactionDraft(memberId: memberId, type: type, amount: (body["amount"] as? NSNumber)?.doubleValue,
                                         count: body["points_change"] as? Int, invoiceNo: body["invoice_no"] as? String,
                                         serviceId: body["service_id"] as? Int)
            let service = draft.serviceId == 7 ? Service(id: 7, name: "غسيل", price: 25) : nil
            switch RewardRules.evaluate(draft, shop: shop, balance: member.currentBalance, service: service) {
            case .failure(let e):
                return respond(422, ["success": false, "message": e.message])
            case .success(let change):
                member.currentBalance += type == .earn ? change : -change
                members[memberId] = member
                clock += 1
                memberUpdatedAt[memberId] = clock
                let tx = ServerTransaction(id: transactions.count + 1, memberId: memberId, memberName: member.name, pointsChange: change, type: type, createdBy: "كاشير")
                transactions.append((uuid, tx))
                if dropNextResponse {
                    dropNextResponse = false
                    throw URLError(.networkConnectionLost)
                }
                return respond(201, ["success": true, "data": txJSON(tx)])
            }
        default:
            return respond(404, ["message": "Not found"])
        }
    }

    var userJSON: [String: Any] {
        ["id": 1, "name": "كاشير", "email": "c@x.com", "is_active": true, "shop_id": role == "super_admin" ? NSNull() : shop.id as Any, "vehicle_module_enabled": false,
         "role": role, "permissions": role == "super_admin" ? [] : ["members.view-any", "members.create", "transactions.create"]]
    }

    var shopJSON: [String: Any] {
        ["id": shop.id, "name": shop.name, "reward_type": shop.rewardType.rawValue, "number_of_stamps": shop.numberOfStamps as Any,
         "min_stamp_amount": shop.minStampAmount.map { String(format: "%.2f", $0) } as Any, "points_per_amount": "\(shop.pointsPerAmount)",
         "vehicle_module_enabled": false, "is_expired": false]
    }

    func memberJSON(_ m: Member) -> [String: Any] {
        ["id": m.id, "shop_id": m.shopId, "name": m.name, "phone": m.phone as Any, "external_id": m.externalId as Any,
         "current_balance": m.currentBalance, "redeem_count": m.redeemCount, "vehicles": [], "created_at": "2026-10-01 10:00:00"]
    }

    func txJSON(_ t: ServerTransaction) -> [String: Any] {
        ["id": t.id, "member_id": t.memberId, "points_change": t.pointsChange, "type": t.type.rawValue, "amount": NSNull(),
         "created_by": t.createdBy as Any, "created_at": "2026-10-13 12:00:00", "member": memberJSON(members[t.memberId]!)]
    }

    private func respond(_ status: Int, _ json: [String: Any]) -> (Data, HTTPURLResponse) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return (data, HTTPURLResponse(url: URL(string: "https://rasid.pro")!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

// MARK: - Tests

final class RewardRulesTests: XCTestCase {
    let pointsShop = Shop(id: 1, name: "قهوة", rewardType: .points, pointsPerAmount: 0.5)
    let stampsShop = Shop(id: 1, name: "قهوة", rewardType: .stamps, numberOfStamps: 6)
    let minStampShop = Shop(id: 1, name: "قهوة", rewardType: .stamps, numberOfStamps: 5, minStampAmount: 15)
    let visitsShop = Shop(id: 1, name: "مغسلة", rewardType: .visits, initialPoints: 10)

    func testPointsEarnScalesWithAmountAndRoundsDown() {
        let draft = TransactionDraft(memberId: 1, type: .earn, amount: 37, invoiceNo: "A1")
        XCTAssertEqual(RewardRules.evaluate(draft, shop: pointsShop, balance: 0, service: nil), .success(18))
    }

    func testPointsEarnRequiresAmountAndInvoice() {
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .earn, invoiceNo: "A1"), shop: pointsShop, balance: 0, service: nil), .failure(.amountRequired))
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .earn, amount: 10, invoiceNo: "  "), shop: pointsShop, balance: 0, service: nil), .failure(.invoiceRequired))
    }

    func testPointsEarnWithServiceUsesServicePriceAndNeedsNoInvoice() {
        let draft = TransactionDraft(memberId: 1, type: .earn, serviceId: 7)
        XCTAssertEqual(RewardRules.evaluate(draft, shop: pointsShop, balance: 0, service: Service(id: 7, name: "غسيل", price: 40)), .success(20))
    }

    func testPointsRedeemChecksBalance() {
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .redeem, count: 50), shop: pointsShop, balance: 49, service: nil), .failure(.insufficientBalance(needed: 50, available: 49)))
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .redeem, count: 50), shop: pointsShop, balance: 50, service: nil), .success(50))
    }

    func testStampsEarnDefaultsToOneAndHonoursMinimumAmount() {
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .earn, invoiceNo: "A"), shop: stampsShop, balance: 0, service: nil), .success(1))
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .earn, amount: 14.99, invoiceNo: "A"), shop: minStampShop, balance: 0, service: nil), .failure(.belowMinimumStampAmount(15)))
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .earn, amount: 15, invoiceNo: "A"), shop: minStampShop, balance: 0, service: nil), .success(1))
    }

    func testStampsRedeemTakesAFullCard() {
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .redeem), shop: stampsShop, balance: 5, service: nil), .failure(.insufficientBalance(needed: 6, available: 5)))
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .redeem), shop: stampsShop, balance: 7, service: nil), .success(6))
    }

    func testVisits() {
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .earn), shop: visitsShop, balance: 0, service: nil), .failure(.countRequired))
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .earn, count: 10), shop: visitsShop, balance: 0, service: nil), .success(10))
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .earn, serviceId: 7), shop: visitsShop, balance: 0, service: Service(id: 7, name: "غسيل", price: nil)), .success(1))
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .redeem), shop: visitsShop, balance: 0, service: nil), .failure(.insufficientBalance(needed: 1, available: 0)))
        XCTAssertEqual(RewardRules.evaluate(TransactionDraft(memberId: 1, type: .redeem), shop: visitsShop, balance: 3, service: nil), .success(1))
    }

    func testBalanceSummary() {
        XCTAssertEqual(BalanceSummary.make(shop: stampsShop, balance: 4).headline, "4 / 6")
        XCTAssertTrue(BalanceSummary.make(shop: stampsShop, balance: 6).rewardAvailable)
        XCTAssertEqual(BalanceSummary.make(shop: visitsShop, balance: 0).detail, "لا يوجد رصيد زيارات")
    }

    func testRequestBodyCarriesIdempotencyKey() throws {
        let id = UUID()
        let body = RewardRules.requestBody(for: TransactionDraft(memberId: 3, type: .redeem, count: 20), clientUUID: id)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as! [String: Any]
        XCTAssertEqual(json["client_uuid"] as? String, id.uuidString.lowercased())
        XCTAssertEqual(json["points_change"] as? Int, 20)
        XCTAssertNil(json["invoice_no"])
    }
}

final class DecodingTests: XCTestCase {
    func testLaravelStringNumbersDecode() throws {
        let json = """
        {"id":"5","name":"محل","reward_type":"stamps","number_of_stamps":"6","min_stamp_amount":"15.00","points_per_amount":"1.50","is_expired":false}
        """
        let shop = try JSONDecoder().decode(Shop.self, from: Data(json.utf8))
        XCTAssertEqual(shop.id, 5)
        XCTAssertEqual(shop.numberOfStamps, 6)
        XCTAssertEqual(shop.minStampAmount, 15)
        XCTAssertEqual(shop.pointsPerAmount, 1.5)
    }

    func testUnknownRewardTypeFallsBackToPoints() throws {
        let shop = try JSONDecoder().decode(Shop.self, from: Data(#"{"id":1,"name":"x","reward_type":"cashback"}"#.utf8))
        XCTAssertEqual(shop.rewardType, .points)
    }

    func testSoftDeletedVehiclesAreDropped() throws {
        let json = #"{"id":1,"shop_id":2,"name":"علي","current_balance":"12","vehicles":[{"id":1,"member_id":1,"plate_number":"123","deleted_at":null},{"id":2,"member_id":1,"plate_number":"999","deleted_at":"2026-01-01 00:00:00"}]}"#
        let member = try JSONDecoder().decode(Member.self, from: Data(json.utf8))
        XCTAssertEqual(member.currentBalance, 12)
        XCTAssertEqual(member.vehicles.map(\.id), [1])
    }

    func testValidationErrorMessageIsSurfaced() {
        let data = Data(#"{"message":"The given data was invalid.","errors":{"phone":["رقم الهاتف مستخدم بالفعل"]}}"#.utf8)
        XCTAssertEqual(APIClient.mapError(status: 422, data: data), .rejected(status: 422, message: "رقم الهاتف مستخدم بالفعل"))
        XCTAssertEqual(APIClient.mapError(status: 403, data: Data(#"{"shop_expired":true,"message":"انتهى"}"#.utf8)), .shopExpired("انتهى"))
        XCTAssertEqual(APIClient.mapError(status: 502, data: Data("<html>".utf8)).isTransient, true)
    }
}

final class SyncTests: XCTestCase {
    func makeServer(rewardType: RewardType = .points) -> FakeServer {
        let shop = Shop(id: 9, name: "محل", rewardType: rewardType, numberOfStamps: 6, pointsPerAmount: 1)
        return FakeServer(shop: shop, members: [
            Member(id: 1, shopId: 9, name: "سارة", phone: "0551112222", externalId: "EXT_000001", currentBalance: 100),
            Member(id: 2, shopId: 9, name: "خالد", phone: "0553334444", externalId: "EXT_000002", currentBalance: 0),
            Member(id: 3, shopId: 9, name: "منى", phone: "0555556666", externalId: "EXT_000003", currentBalance: 6),
        ])
    }

    func makeEngine(_ server: FakeServer, file: URL? = nil) -> SyncEngine {
        SyncEngine(store: LocalStore(fileURL: file), api: APIClient(token: "good-token", transport: server))
    }

    func testLoginSuccessAndWrongPassword() async throws {
        let server = makeServer()
        let api = APIClient(transport: server)
        let result = try await api.login(email: "c@x.com", password: "secret")
        XCTAssertEqual(result.token, "good-token")
        XCTAssertEqual(result.user.role, .cashier)
        do {
            _ = try await api.login(email: "c@x.com", password: "wrong")
            XCTFail("expected failure")
        } catch let error as APIError {
            XCTAssertEqual(error, .rejected(status: 401, message: "البريد الإلكتروني أو كلمة المرور غير صحيحة."))
        }
    }

    func testFullDownloadIsPagedAndSearchable() async throws {
        let server = makeServer()
        let engine = makeEngine(server)
        let report = try await engine.sync()
        XCTAssertEqual(report.membersUpdated, 3)
        XCTAssertFalse(report.offline)
        let snapshot = await engine.store.snapshot
        XCTAssertEqual(snapshot.members.count, 3)
        XCTAssertEqual(snapshot.services.first?.price, 25)
        XCTAssertEqual(server.requests.filter { $0 == "GET app/members" }.count, 2, "3 members at page size 2 = 2 pages")
        let byPhone = await engine.store.findMember(code: "٠٥٥١١١٢٢٢٢")
        XCTAssertEqual(byPhone?.id, 1)
        let byCode = await engine.store.findMember(code: "ext_000003")
        XCTAssertEqual(byCode?.id, 3)
        let search = await engine.store.searchMembers("خالد")
        XCTAssertEqual(search.map(\.id), [2])
    }

    func testOfflineOperationsQueueAndSyncLater() async throws {
        let server = makeServer()
        let engine = makeEngine(server)
        _ = try await engine.sync()

        server.online = false
        try await engine.store.enqueue(TransactionDraft(memberId: 1, type: .redeem, count: 30))
        try await engine.store.enqueue(TransactionDraft(memberId: 2, type: .earn, amount: 40, invoiceNo: "F-9"))
        let redeemedBalance = await engine.store.displayBalance(memberId: 1)
        XCTAssertEqual(redeemedBalance, 70)
        let earnedBalance = await engine.store.displayBalance(memberId: 2)
        XCTAssertEqual(earnedBalance, 40)

        let offlineReport = try await engine.sync()
        XCTAssertTrue(offlineReport.offline)
        let stillPending = await engine.store.pendingOperations.count
        XCTAssertEqual(stillPending, 2)

        server.online = true
        let report = try await engine.sync()
        XCTAssertEqual(report.sent, 2)
        XCTAssertEqual(server.members[1]?.currentBalance, 70)
        XCTAssertEqual(server.members[2]?.currentBalance, 40)
        let pendingAfter = await engine.store.pendingOperations.count
        XCTAssertEqual(pendingAfter, 0)
        let finalBalance = await engine.store.displayBalance(memberId: 1)
        XCTAssertEqual(finalBalance, 70)
    }

    func testLostResponseIsNotAppliedTwice() async throws {
        let server = makeServer()
        let engine = makeEngine(server)
        _ = try await engine.sync()

        try await engine.store.enqueue(TransactionDraft(memberId: 2, type: .earn, amount: 10, invoiceNo: "X"))
        server.dropNextResponse = true
        let first = try await engine.sync()
        XCTAssertTrue(first.offline, "a lost response must look like an outage")
        XCTAssertEqual(server.members[2]?.currentBalance, 10, "server applied it once")
        let shownWhilePending = await engine.store.displayBalance(memberId: 2)
        XCTAssertEqual(shownWhilePending, 10, "pull was skipped, so it is not double counted")

        let second = try await engine.sync()
        XCTAssertEqual(second.sent, 1)
        XCTAssertEqual(server.transactions.count, 1, "retry with the same client_uuid did not create a second transaction")
        XCTAssertEqual(server.members[2]?.currentBalance, 10)
        let finalBalance = await engine.store.displayBalance(memberId: 2)
        XCTAssertEqual(finalBalance, 10)
    }

    func testServerRejectionStopsAffectingBalance() async throws {
        let server = makeServer()
        let engine = makeEngine(server)
        _ = try await engine.sync()

        // Two devices: another cashier spends the points before this queue is sent.
        server.online = false
        try await engine.store.enqueue(TransactionDraft(memberId: 1, type: .redeem, count: 80))
        server.online = true
        server.members[1]?.currentBalance = 50
        server.clock += 1
        server.memberUpdatedAt[1] = server.clock

        let report = try await engine.sync()
        XCTAssertEqual(report.rejected, 1)
        let rejected = await engine.store.snapshot.pending.first
        XCTAssertEqual(rejected?.status, .rejected)
        XCTAssertNotNil(rejected?.lastError)
        let balance = await engine.store.displayBalance(memberId: 1)
        XCTAssertEqual(balance, 50, "rejected op no longer counts; server balance wins")
    }

    func testLocalValidationBlocksOverRedeemOffline() async throws {
        let server = makeServer(rewardType: .stamps)
        let engine = makeEngine(server)
        _ = try await engine.sync()
        server.online = false
        try await engine.store.enqueue(TransactionDraft(memberId: 3, type: .redeem))
        do {
            try await engine.store.enqueue(TransactionDraft(memberId: 3, type: .redeem))
            XCTFail("second redeem must be refused locally")
        } catch let error as RewardRuleError {
            XCTAssertEqual(error, .insufficientBalance(needed: 6, available: 0))
        }
    }

    func testDeltaSyncAndDeletedMembers() async throws {
        let server = makeServer()
        let engine = makeEngine(server)
        _ = try await engine.sync()
        server.requests.removeAll()

        server.clock += 1
        server.members[2]?.currentBalance = 55
        server.memberUpdatedAt[2] = server.clock
        server.members[3] = nil

        let report = try await engine.sync()
        XCTAssertEqual(report.membersUpdated, 1, "only the changed member is downloaded")
        let snapshot = await engine.store.snapshot
        XCTAssertEqual(snapshot.members[2]?.currentBalance, 55)
        XCTAssertNil(snapshot.members[3], "member deleted on the server is removed locally")
    }

    func testStorePersistsAcrossLaunches() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = dir.appendingPathComponent("store.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let server = makeServer()
        let engine = makeEngine(server, file: file)
        _ = try await engine.sync()
        server.online = false
        try await engine.store.enqueue(TransactionDraft(memberId: 2, type: .earn, amount: 5, invoiceNo: "P"))

        let relaunched = LocalStore(fileURL: file)
        let count = await relaunched.snapshot.members.count
        XCTAssertEqual(count, 3)
        let pending = await relaunched.pendingOperations.count
        XCTAssertEqual(pending, 1)
        let balance = await relaunched.displayBalance(memberId: 2)
        XCTAssertEqual(balance, 5)
    }

    func testExpiredShopSurfacesAndKeepsQueue() async throws {
        let server = makeServer()
        let engine = makeEngine(server)
        _ = try await engine.sync()
        try await engine.store.enqueue(TransactionDraft(memberId: 2, type: .earn, amount: 5, invoiceNo: "P"))
        server.expiredShop = true
        do {
            _ = try await engine.sync()
            XCTFail("expected shopExpired")
        } catch let error as APIError {
            XCTAssertEqual(error, .shopExpired("انتهى اشتراك المحل"))
        }
        let pending = await engine.store.pendingOperations.count
        XCTAssertEqual(pending, 1)
    }

    func testSuperAdminPicksAShopThenSyncsIt() async throws {
        let server = makeServer()
        server.role = "super_admin"
        let engine = makeEngine(server)

        // Before choosing a shop: only the bootstrap, no member download.
        let first = try await engine.sync()
        XCTAssertFalse(first.offline)
        let before = await engine.store.snapshot
        XCTAssertEqual(before.user?.isSuperAdmin, true)
        XCTAssertNil(before.shop)
        XCTAssertTrue(before.members.isEmpty)
        XCTAssertEqual(server.requests.filter { $0.hasPrefix("GET app/members") }.count, 0)

        try await engine.store.selectShop(server.shop)
        let second = try await engine.sync()
        XCTAssertEqual(second.membersUpdated, 3)
        XCTAssertTrue(server.shopIdsSeen.suffix(4).allSatisfy { $0 == "9" }, "every app/* call names the shop")
        let after = await engine.store.snapshot
        XCTAssertEqual(after.selectedShopId, 9)
        XCTAssertEqual(after.user?.isSuperAdmin, true, "switching shop keeps the session")

        // Super admin can transact like a cashier (server allows it for super_admin).
        try await engine.store.enqueue(TransactionDraft(memberId: 2, type: .earn, amount: 20, invoiceNo: "SA-1"))
        let third = try await engine.sync()
        XCTAssertEqual(third.sent, 1)
        XCTAssertEqual(server.members[2]?.currentBalance, 20)
    }

    func testStaffNeverSendShopId() async throws {
        let server = makeServer()
        _ = try await makeEngine(server).sync()
        XCTAssertTrue(server.shopIdsSeen.allSatisfy { $0 == nil })
    }

    func testCannotSwitchShopWithUnsentOperations() async throws {
        let server = makeServer()
        server.role = "super_admin"
        let engine = makeEngine(server)
        try await engine.store.selectShop(server.shop)
        _ = try await engine.sync()
        server.online = false
        try await engine.store.enqueue(TransactionDraft(memberId: 1, type: .redeem, count: 10))
        do {
            try await engine.store.selectShop(Shop(id: 10, name: "آخر", rewardType: .points))
            XCTFail("must refuse while an operation is unsent")
        } catch let error as APIError {
            XCTAssertEqual(error, .rejected(status: 409, message: "يوجد عمليات لم تُرسل بعد. انتظر المزامنة قبل تغيير المحل."))
        }
    }

    func testStoreMessageReachAndPermissions() async throws {
        let server = makeServer()
        let engine = makeEngine(server)
        _ = try await engine.sync()
        let reach = await engine.store.snapshot.walletReach
        XCTAssertEqual(reach, WalletReach(cards: 3, devices: 5), "bootstrap carries the Wallet audience (numbers may arrive as strings)")

        do {
            _ = try await engine.api.sendStoreMessage(shopId: 9, message: "عرض اليوم")
            XCTFail("a cashier must not be able to message customers")
        } catch let error as APIError {
            XCTAssertEqual(error, .rejected(status: 403, message: "لا تملك صلاحية إرسال رسائل لعملاء هذا المحل."))
        }

        server.role = "shop_manager"
        let sent = try await engine.api.sendStoreMessage(shopId: 9, message: "عرض اليوم: القهوة الثانية مجاناً")
        XCTAssertEqual(sent, WalletReach(cards: 3, devices: 5))
        XCTAssertEqual(server.storeMessage, "عرض اليوم: القهوة الثانية مجاناً")

        do {
            _ = try await engine.api.sendStoreMessage(shopId: 9, message: "")
            XCTFail("empty message must be refused")
        } catch let error as APIError {
            XCTAssertEqual(error, .rejected(status: 422, message: "الرسالة مطلوبة."))
        }
    }
}
