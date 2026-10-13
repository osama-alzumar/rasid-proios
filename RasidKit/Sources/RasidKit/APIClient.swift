import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum APIError: Error, Equatable, Sendable {
    /// No connection, timeout or DNS failure — the request may be retried.
    case offline
    /// Token missing, revoked or expired: the user must log in again.
    case unauthorized
    case accountDisabled(String)
    case shopExpired(String)
    /// The server understood and rejected the request (validation, business rule).
    case rejected(status: Int, message: String)
    /// 5xx or an unreadable response — retry later.
    case server(status: Int, message: String)

    public var message: String {
        switch self {
        case .offline: return "لا يوجد اتصال بالخادم."
        case .unauthorized: return "انتهت الجلسة، سجّل الدخول من جديد."
        case .accountDisabled(let m), .shopExpired(let m), .rejected(_, let m): return m
        case .server(let status, _): return "تعذر الاتصال بالخادم (\(status)). حاول لاحقاً."
        }
    }

    /// True when retrying the same request later can succeed.
    public var isTransient: Bool {
        switch self {
        case .offline, .server: return true
        default: return false
        }
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: 0, message: "Invalid response")
        }
        return (data, http)
    }
}

public struct LoginResult: Sendable {
    public var user: User
    public var token: String
}

public struct BootstrapPayload: Decodable, Sendable {
    public var serverTime: String
    public var user: User
    public var shop: Shop?
    public var services: [Service]

    enum CodingKeys: String, CodingKey {
        case user, shop, services
        case serverTime = "server_time"
    }

    public init(serverTime: String, user: User, shop: Shop?, services: [Service]) {
        self.serverTime = serverTime
        self.user = user
        self.shop = shop
        self.services = services
    }
}

public struct MembersPage: Decodable, Sendable {
    public struct Meta: Decodable, Sendable {
        public var serverTime: String
        public var hasMore: Bool
        public var nextAfterId: Int?
        public var allIds: [Int]?

        enum CodingKeys: String, CodingKey {
            case serverTime = "server_time"
            case hasMore = "has_more"
            case nextAfterId = "next_after_id"
            case allIds = "all_ids"
        }

        public init(serverTime: String, hasMore: Bool, nextAfterId: Int?, allIds: [Int]?) {
            self.serverTime = serverTime
            self.hasMore = hasMore
            self.nextAfterId = nextAfterId
            self.allIds = allIds
        }
    }

    public var data: [Member]
    public var meta: Meta

    public init(data: [Member], meta: Meta) {
        self.data = data
        self.meta = meta
    }
}

public struct TransactionResult: Sendable, Equatable {
    public var transaction: ServerTransaction
    public var alreadyApplied: Bool
}

/// Thin client for the Laravel API at https://rasid.pro/backend/api.
public struct APIClient: Sendable {
    public static let production = URL(string: "https://rasid.pro/backend/api/")!

    public var baseURL: URL
    public var token: String?
    private let transport: HTTPTransport

    public init(baseURL: URL = APIClient.production, token: String? = nil, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
    }

    // MARK: Endpoints

    public func login(email: String, password: String) async throws -> LoginResult {
        struct Body: Encodable { let email: String; let password: String }
        struct Payload: Decodable { let user: User; let token: String }
        do {
            let payload: Payload = try await request("POST", "login", body: Body(email: email, password: password), envelope: true)
            return LoginResult(user: payload.user, token: payload.token)
        } catch APIError.unauthorized {
            // On /login a 401 means wrong credentials, not an expired session.
            throw APIError.rejected(status: 401, message: "البريد الإلكتروني أو كلمة المرور غير صحيحة.")
        }
    }

    public func logout() async throws {
        struct Empty: Encodable {}
        let _: IgnoredBody = try await request("POST", "logout", body: Empty(), envelope: false)
    }

    public func bootstrap() async throws -> BootstrapPayload {
        try await request("GET", "app/bootstrap", envelope: true)
    }

    public func members(since: String?, afterId: Int) async throws -> MembersPage {
        var query = [URLQueryItem(name: "after_id", value: String(afterId))]
        if let since { query.append(URLQueryItem(name: "since", value: since)) }
        return try await request("GET", "app/members", query: query, envelope: false)
    }

    public func recentTransactions(limit: Int = 100) async throws -> [ServerTransaction] {
        try await request("GET", "app/transactions", query: [URLQueryItem(name: "limit", value: String(limit))], envelope: true)
    }

    public func lookupMember(code: String) async throws -> Member {
        let escaped = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? code
        return try await request("GET", "members/lookup/\(escaped)", envelope: true)
    }

    public func createMember(name: String, phone: String?) async throws -> Member {
        var body: [String: AnyEncodable] = ["name": AnyEncodable(name)]
        if let phone, !phone.isEmpty { body["phone"] = AnyEncodable(phone) }
        return try await request("POST", "members", body: body, envelope: true)
    }

    public func createVehicle(memberId: Int, lettersAr: String, number: String, make: String?, model: String?, color: String?) async throws -> Vehicle {
        var body: [String: AnyEncodable] = [
            "member_id": AnyEncodable(memberId),
            "plate_letters_ar": AnyEncodable(lettersAr),
            "plate_number": AnyEncodable(number),
        ]
        if let make, !make.isEmpty { body["make"] = AnyEncodable(make) }
        if let model, !model.isEmpty { body["model"] = AnyEncodable(model) }
        if let color, !color.isEmpty { body["color"] = AnyEncodable(color) }
        return try await request("POST", "vehicles", body: body, envelope: true)
    }

    public func createTransaction(_ draft: TransactionDraft, clientUUID: UUID) async throws -> TransactionResult {
        struct Payload: Decodable {
            let data: ServerTransaction
            let alreadyApplied: Bool?
            enum CodingKeys: String, CodingKey {
                case data
                case alreadyApplied = "already_applied"
            }
        }
        let payload: Payload = try await request("POST", "transactions", body: RewardRules.requestBody(for: draft, clientUUID: clientUUID), envelope: false)
        return TransactionResult(transaction: payload.data, alreadyApplied: payload.alreadyApplied ?? false)
    }

    public func dashboardStats(period: String) async throws -> DashboardStats {
        try await request("GET", "dashboard/stats", query: [URLQueryItem(name: "period", value: period)], envelope: true)
    }

    // MARK: Plumbing

    private struct Envelope<T: Decodable>: Decodable { let data: T }
    private struct IgnoredBody: Decodable {}
    private struct ErrorBody: Decodable {
        let message: String?
        let errors: [String: [String]]?
        let shopExpired: Bool?
        enum CodingKeys: String, CodingKey {
            case message, errors
            case shopExpired = "shop_expired"
        }
    }

    private func request<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [], body: (any Encodable)? = nil, envelope: Bool) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ar", forHTTPHeaderField: "Accept-Language")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.offline
        }

        guard (200..<300).contains(response.statusCode) else {
            throw Self.mapError(status: response.statusCode, data: data)
        }
        if T.self == IgnoredBody.self { return IgnoredBody() as! T }
        do {
            let decoder = JSONDecoder()
            return envelope ? try decoder.decode(Envelope<T>.self, from: data).data : try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.server(status: response.statusCode, message: "Unreadable response: \(error)")
        }
    }

    static func mapError(status: Int, data: Data) -> APIError {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        let firstFieldError = body?.errors?.values.first?.first
        let message = firstFieldError ?? body?.message ?? "حدث خطأ غير متوقع."
        switch status {
        case 401:
            return .unauthorized
        case 403 where body?.shopExpired == true:
            return .shopExpired(message)
        case 403 where message.contains("تعطيل"):
            return .accountDisabled(message)
        case 400..<500:
            return .rejected(status: status, message: message)
        default:
            return .server(status: status, message: message)
        }
    }
}
