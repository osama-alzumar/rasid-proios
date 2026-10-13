import Foundation

/// What the cashier filled in for one earn/redeem operation.
public struct TransactionDraft: Codable, Sendable, Hashable {
    public var memberId: Int
    public var type: TransactionType
    public var amount: Double?
    /// Points to redeem (points shops) or stamps/visits to add on earn.
    public var count: Int?
    public var invoiceNo: String?
    public var vehicleId: Int?
    public var serviceId: Int?

    public init(memberId: Int, type: TransactionType, amount: Double? = nil, count: Int? = nil, invoiceNo: String? = nil, vehicleId: Int? = nil, serviceId: Int? = nil) {
        self.memberId = memberId
        self.type = type
        self.amount = amount
        self.count = count
        self.invoiceNo = invoiceNo
        self.vehicleId = vehicleId
        self.serviceId = serviceId
    }
}

public enum RewardRuleError: Error, Equatable, Sendable {
    case amountRequired
    case invoiceRequired
    case countRequired
    case belowMinimumStampAmount(Double)
    case insufficientBalance(needed: Int, available: Int)

    public var message: String {
        switch self {
        case .amountRequired:
            return "أدخل قيمة الفاتورة."
        case .invoiceRequired:
            return "أدخل رقم الفاتورة."
        case .countRequired:
            return "أدخل العدد."
        case .belowMinimumStampAmount(let min):
            return "الحد الأدنى لاحتساب الختم هو \(Formatting.amount(min)) ريال — قيمة الفاتورة المدخلة أقل من ذلك."
        case .insufficientBalance(let needed, let available):
            return "الرصيد غير كافٍ: المطلوب \(needed) والمتاح \(available)."
        }
    }
}

/// Local mirror of the server's RewardStrategy classes and
/// StoreTransactionRequest rules, so an operation recorded offline gets the
/// same validation and the same balance change the server will apply.
public enum RewardRules {
    /// Fields the transaction form must show for this shop and operation.
    public struct FormSpec: Equatable, Sendable {
        public var showsAmount: Bool
        public var amountRequired: Bool
        public var showsInvoice: Bool
        public var invoiceRequired: Bool
        public var showsCount: Bool
        public var countRequired: Bool
    }

    public static func formSpec(shop: Shop, type: TransactionType, hasService: Bool) -> FormSpec {
        switch (shop.rewardType, type) {
        case (.points, .earn):
            return FormSpec(showsAmount: !hasService, amountRequired: !hasService,
                            showsInvoice: true, invoiceRequired: !hasService,
                            showsCount: false, countRequired: false)
        case (.points, .redeem):
            return FormSpec(showsAmount: false, amountRequired: false,
                            showsInvoice: false, invoiceRequired: false,
                            showsCount: true, countRequired: true)
        case (.stamps, .earn):
            let needsAmount = shop.minStampAmount != nil
            return FormSpec(showsAmount: needsAmount, amountRequired: needsAmount,
                            showsInvoice: true, invoiceRequired: !hasService,
                            showsCount: true, countRequired: false)
        case (.visits, .earn):
            return FormSpec(showsAmount: false, amountRequired: false,
                            showsInvoice: true, invoiceRequired: false,
                            showsCount: !hasService, countRequired: !hasService)
        case (.stamps, .redeem), (.visits, .redeem):
            return FormSpec(showsAmount: false, amountRequired: false,
                            showsInvoice: false, invoiceRequired: false,
                            showsCount: false, countRequired: false)
        }
    }

    /// Validates the draft and returns the absolute balance change
    /// (the server's `points_change`). Earn adds it, redeem subtracts it.
    public static func evaluate(_ draft: TransactionDraft, shop: Shop, balance: Int, service: Service?) -> Result<Int, RewardRuleError> {
        var amount = draft.amount
        var count = draft.count
        let invoice = draft.invoiceNo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasService = service != nil

        // Same substitution the server does for a picked service on earn.
        if draft.type == .earn, let service {
            if amount == nil, let price = service.price { amount = price }
            if count == nil { count = 1 }
        }

        let spec = formSpec(shop: shop, type: draft.type, hasService: hasService)
        if spec.amountRequired && amount == nil { return .failure(.amountRequired) }
        if spec.invoiceRequired && (invoice ?? "").isEmpty { return .failure(.invoiceRequired) }
        if spec.countRequired && (count ?? 0) < 1 { return .failure(.countRequired) }

        switch (shop.rewardType, draft.type) {
        case (.points, .earn):
            return .success(Int(((amount ?? 0) * shop.pointsPerAmount).rounded(.down)))
        case (.points, .redeem):
            let points = count ?? 0
            return balance < points ? .failure(.insufficientBalance(needed: points, available: balance)) : .success(points)
        case (.stamps, .earn):
            if let min = shop.minStampAmount, (amount ?? -1) < min {
                return .failure(.belowMinimumStampAmount(min))
            }
            return .success(max(1, count ?? 1))
        case (.stamps, .redeem):
            let needed = shop.stampsPerReward
            return balance < needed ? .failure(.insufficientBalance(needed: needed, available: balance)) : .success(needed)
        case (.visits, .earn):
            return .success(count ?? 0)
        case (.visits, .redeem):
            return balance < 1 ? .failure(.insufficientBalance(needed: 1, available: balance)) : .success(1)
        }
    }

    /// Request body for POST /transactions.
    public static func requestBody(for draft: TransactionDraft, clientUUID: UUID) -> [String: AnyEncodable] {
        var body: [String: AnyEncodable] = [
            "member_id": AnyEncodable(draft.memberId),
            "type": AnyEncodable(draft.type.rawValue),
            "client_uuid": AnyEncodable(clientUUID.uuidString.lowercased()),
        ]
        if let amount = draft.amount { body["amount"] = AnyEncodable(amount) }
        if let count = draft.count { body["points_change"] = AnyEncodable(count) }
        if let invoice = draft.invoiceNo?.trimmingCharacters(in: .whitespacesAndNewlines), !invoice.isEmpty {
            body["invoice_no"] = AnyEncodable(invoice)
        }
        if let vehicleId = draft.vehicleId { body["vehicle_id"] = AnyEncodable(vehicleId) }
        if let serviceId = draft.serviceId { body["service_id"] = AnyEncodable(serviceId) }
        return body
    }
}

/// What a member's balance means for the shop's reward type, for display.
public struct BalanceSummary: Equatable, Sendable {
    public var headline: String
    public var unit: String
    public var detail: String?
    public var progress: Double?
    public var rewardAvailable: Bool

    public static func make(shop: Shop, balance: Int) -> BalanceSummary {
        switch shop.rewardType {
        case .points:
            return BalanceSummary(headline: "\(balance)", unit: "نقطة", detail: nil, progress: nil, rewardAvailable: balance > 0)
        case .stamps:
            let total = shop.stampsPerReward
            let current = min(balance, total)
            let ready = balance >= total
            return BalanceSummary(headline: "\(current) / \(total)", unit: "ختم",
                                  detail: ready ? "المكافأة جاهزة للاستبدال" : "باقي \(total - current) للمكافأة",
                                  progress: Double(current) / Double(total), rewardAvailable: ready)
        case .visits:
            return BalanceSummary(headline: "\(balance)", unit: "زيارة متبقية",
                                  detail: balance > 0 ? nil : "لا يوجد رصيد زيارات",
                                  progress: nil, rewardAvailable: balance > 0)
        }
    }
}

/// Type-erased Encodable for building JSON request bodies.
public struct AnyEncodable: Encodable, Sendable, Equatable {
    private let value: Value

    private enum Value: Equatable, Sendable {
        case int(Int), double(Double), string(String)
    }

    public init(_ int: Int) { value = .int(int) }
    public init(_ double: Double) { value = .double(double) }
    public init(_ string: String) { value = .string(string) }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        }
    }
}

public enum Formatting {
    public static func amount(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}
