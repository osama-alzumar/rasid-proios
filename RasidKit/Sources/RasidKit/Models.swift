import Foundation

// Mirrors of the Laravel API resources (UserResource, ShopResource, ...).
// Laravel serialises decimal columns as strings ("15.00") and some integer
// columns as strings depending on the MySQL driver, so numeric fields go
// through the lenient decoders in Flexible.swift.

public enum RewardType: String, Codable, Sendable, Equatable {
    case points, stamps, visits

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RewardType(rawValue: raw) ?? .points
    }
}

public enum UserRole: String, Codable, Sendable, Equatable {
    case cashier
    case shopManager = "shop_manager"
    case superAdmin = "super_admin"
    case marketer
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = raw.flatMap(UserRole.init(rawValue:)) ?? .unknown
    }
}

public struct User: Codable, Sendable, Equatable {
    public var id: Int
    public var name: String
    public var email: String
    public var isActive: Bool
    public var shopId: Int?
    public var vehicleModuleEnabled: Bool
    public var role: UserRole
    public var permissions: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, email, role, permissions
        case isActive = "is_active"
        case shopId = "shop_id"
        case vehicleModuleEnabled = "vehicle_module_enabled"
    }

    public init(id: Int, name: String, email: String, isActive: Bool = true, shopId: Int?, vehicleModuleEnabled: Bool = false, role: UserRole, permissions: [String]) {
        self.id = id
        self.name = name
        self.email = email
        self.isActive = isActive
        self.shopId = shopId
        self.vehicleModuleEnabled = vehicleModuleEnabled
        self.role = role
        self.permissions = permissions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.flexibleInt(.id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        shopId = try c.flexibleIntIfPresent(.shopId)
        vehicleModuleEnabled = try c.decodeIfPresent(Bool.self, forKey: .vehicleModuleEnabled) ?? false
        role = try c.decodeIfPresent(UserRole.self, forKey: .role) ?? .unknown
        permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
    }

    public func can(_ permission: String) -> Bool {
        role == .superAdmin || permissions.contains(permission)
    }

    public var canCreateTransactions: Bool { can("transactions.create") }
    public var canCreateMembers: Bool { can("members.create") }
    public var canCreateVehicles: Bool { can("vehicles.create") }
    public var isManager: Bool { role == .shopManager }
    public var isSuperAdmin: Bool { role == .superAdmin }
}

public struct StampImage: Codable, Sendable, Equatable {
    public var id: Int
    public var state: Int
    public var imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, state
        case imageUrl = "image_url"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.flexibleInt(.id)
        state = try c.flexibleInt(.state)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
    }
}

public struct Shop: Codable, Sendable, Equatable {
    public var id: Int
    public var name: String
    public var slug: String?
    public var logoUrl: String?
    public var rewardType: RewardType
    public var numberOfStamps: Int?
    public var minStampAmount: Double?
    public var initialPoints: Int?
    public var storeMessage: String?
    public var pointsPerAmount: Double
    public var vehicleModuleEnabled: Bool
    public var expiresAt: String?
    public var isExpired: Bool
    public var stampImages: [StampImage]?
    /// Only on shop lists (GET /shops).
    public var membersCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case logoUrl = "logo_url"
        case rewardType = "reward_type"
        case numberOfStamps = "number_of_stamps"
        case minStampAmount = "min_stamp_amount"
        case initialPoints = "initial_points"
        case storeMessage = "store_message"
        case pointsPerAmount = "points_per_amount"
        case vehicleModuleEnabled = "vehicle_module_enabled"
        case expiresAt = "expires_at"
        case isExpired = "is_expired"
        case stampImages = "stamp_images"
        case membersCount = "members_count"
    }

    public init(id: Int, name: String, rewardType: RewardType, numberOfStamps: Int? = nil, minStampAmount: Double? = nil, initialPoints: Int? = nil, pointsPerAmount: Double = 1, vehicleModuleEnabled: Bool = false) {
        self.id = id
        self.name = name
        self.rewardType = rewardType
        self.numberOfStamps = numberOfStamps
        self.minStampAmount = minStampAmount
        self.initialPoints = initialPoints
        self.pointsPerAmount = pointsPerAmount
        self.vehicleModuleEnabled = vehicleModuleEnabled
        self.isExpired = false
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.flexibleInt(.id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        logoUrl = try c.decodeIfPresent(String.self, forKey: .logoUrl)
        rewardType = try c.decodeIfPresent(RewardType.self, forKey: .rewardType) ?? .points
        numberOfStamps = try c.flexibleIntIfPresent(.numberOfStamps)
        minStampAmount = try c.flexibleDoubleIfPresent(.minStampAmount)
        initialPoints = try c.flexibleIntIfPresent(.initialPoints)
        storeMessage = try c.decodeIfPresent(String.self, forKey: .storeMessage)
        pointsPerAmount = try c.flexibleDoubleIfPresent(.pointsPerAmount) ?? 1
        vehicleModuleEnabled = try c.decodeIfPresent(Bool.self, forKey: .vehicleModuleEnabled) ?? false
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        isExpired = try c.decodeIfPresent(Bool.self, forKey: .isExpired) ?? false
        stampImages = try c.decodeIfPresent([StampImage].self, forKey: .stampImages)
        membersCount = try c.flexibleIntIfPresent(.membersCount)
    }

    /// Stamps needed for one reward (the server treats 0/null as 1).
    public var stampsPerReward: Int { max(numberOfStamps ?? 1, 1) }
}

public struct Service: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var price: Double?
    public var isActive: Bool
    public var sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, price
        case isActive = "is_active"
        case sortOrder = "sort_order"
    }

    public init(id: Int, name: String, price: Double?, isActive: Bool = true, sortOrder: Int? = nil) {
        self.id = id
        self.name = name
        self.price = price
        self.isActive = isActive
        self.sortOrder = sortOrder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.flexibleInt(.id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        price = try c.flexibleDoubleIfPresent(.price)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        sortOrder = try c.flexibleIntIfPresent(.sortOrder)
    }
}

public struct Vehicle: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var memberId: Int
    public var plateLettersAr: String?
    public var plateLettersEn: String?
    public var plateNumber: String?
    public var plateDisplayAr: String?
    public var make: String?
    public var model: String?
    public var color: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, make, model, color
        case memberId = "member_id"
        case plateLettersAr = "plate_letters_ar"
        case plateLettersEn = "plate_letters_en"
        case plateNumber = "plate_number"
        case plateDisplayAr = "plate_display_ar"
        case deletedAt = "deleted_at"
    }

    public init(id: Int, memberId: Int, plateLettersAr: String?, plateNumber: String?, make: String? = nil, model: String? = nil, color: String? = nil) {
        self.id = id
        self.memberId = memberId
        self.plateLettersAr = plateLettersAr
        self.plateNumber = plateNumber
        self.make = make
        self.model = model
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.flexibleInt(.id)
        memberId = try c.flexibleIntIfPresent(.memberId) ?? 0
        plateLettersAr = try c.decodeIfPresent(String.self, forKey: .plateLettersAr)
        plateLettersEn = try c.decodeIfPresent(String.self, forKey: .plateLettersEn)
        plateNumber = try c.flexibleStringIfPresent(.plateNumber)
        plateDisplayAr = try c.decodeIfPresent(String.self, forKey: .plateDisplayAr)
        make = try c.decodeIfPresent(String.self, forKey: .make)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
    }

    public var plateText: String {
        if let display = plateDisplayAr, !display.isEmpty { return display }
        return [plateLettersAr, plateNumber].compactMap { $0 }.joined(separator: " ")
    }

    public var descriptionText: String {
        [make, model, color].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct Member: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var shopId: Int
    public var name: String
    public var phone: String?
    public var externalId: String?
    public var passkitId: String?
    /// Balance as last confirmed by the server — pending offline operations
    /// are applied on top of it by `LocalStore`, never written into it.
    public var currentBalance: Int
    public var redeemCount: Int
    public var vehicles: [Vehicle]
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, phone, vehicles
        case shopId = "shop_id"
        case externalId = "external_id"
        case passkitId = "passkit_id"
        case currentBalance = "current_balance"
        case redeemCount = "redeem_count"
        case createdAt = "created_at"
    }

    public init(id: Int, shopId: Int, name: String, phone: String? = nil, externalId: String? = nil, passkitId: String? = nil, currentBalance: Int = 0, redeemCount: Int = 0, vehicles: [Vehicle] = [], createdAt: String? = nil) {
        self.id = id
        self.shopId = shopId
        self.name = name
        self.phone = phone
        self.externalId = externalId
        self.passkitId = passkitId
        self.currentBalance = currentBalance
        self.redeemCount = redeemCount
        self.vehicles = vehicles
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.flexibleInt(.id)
        shopId = try c.flexibleIntIfPresent(.shopId) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        phone = try c.flexibleStringIfPresent(.phone)
        externalId = try c.flexibleStringIfPresent(.externalId)
        passkitId = try c.flexibleStringIfPresent(.passkitId)
        currentBalance = try c.flexibleIntIfPresent(.currentBalance) ?? 0
        redeemCount = try c.flexibleIntIfPresent(.redeemCount) ?? 0
        vehicles = (try c.decodeIfPresent([Vehicle].self, forKey: .vehicles) ?? []).filter { $0.deletedAt == nil }
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

public enum TransactionType: String, Codable, Sendable, Equatable {
    case earn, redeem
}

public struct ServerTransaction: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var memberId: Int
    public var memberName: String?
    public var vehicleId: Int?
    public var serviceName: String?
    public var invoiceNo: String?
    public var amount: Double?
    public var pointsChange: Int
    public var type: TransactionType
    public var createdBy: String?
    public var createdAt: String?
    /// Server balance of the member right after this transaction, when the
    /// response embedded the member (POST /transactions does).
    public var memberBalanceAfter: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, amount, member
        case memberId = "member_id"
        case memberName = "member_name"
        case vehicleId = "vehicle_id"
        case serviceName = "service_name"
        case invoiceNo = "invoice_no"
        case pointsChange = "points_change"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case memberBalanceAfter = "member_balance_after"
    }

    public init(id: Int, memberId: Int, memberName: String?, pointsChange: Int, type: TransactionType, amount: Double? = nil, invoiceNo: String? = nil, serviceName: String? = nil, createdBy: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.memberId = memberId
        self.memberName = memberName
        self.pointsChange = pointsChange
        self.type = type
        self.amount = amount
        self.invoiceNo = invoiceNo
        self.serviceName = serviceName
        self.createdBy = createdBy
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.flexibleInt(.id)
        memberId = try c.flexibleIntIfPresent(.memberId) ?? 0
        vehicleId = try c.flexibleIntIfPresent(.vehicleId)
        serviceName = try c.decodeIfPresent(String.self, forKey: .serviceName)
        invoiceNo = try c.flexibleStringIfPresent(.invoiceNo)
        amount = try c.flexibleDoubleIfPresent(.amount)
        pointsChange = try c.flexibleIntIfPresent(.pointsChange) ?? 0
        type = try c.decodeIfPresent(TransactionType.self, forKey: .type) ?? .earn
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        // Either our own cached form (member_name) or the API's nested member.
        if let member = try? c.decodeIfPresent(Member.self, forKey: .member) {
            memberName = member.name
            memberBalanceAfter = member.currentBalance
        } else {
            memberName = try c.decodeIfPresent(String.self, forKey: .memberName)
            memberBalanceAfter = try c.flexibleIntIfPresent(.memberBalanceAfter)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(memberId, forKey: .memberId)
        try c.encodeIfPresent(memberName, forKey: .memberName)
        try c.encodeIfPresent(vehicleId, forKey: .vehicleId)
        try c.encodeIfPresent(serviceName, forKey: .serviceName)
        try c.encodeIfPresent(invoiceNo, forKey: .invoiceNo)
        try c.encodeIfPresent(amount, forKey: .amount)
        try c.encode(pointsChange, forKey: .pointsChange)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(memberBalanceAfter, forKey: .memberBalanceAfter)
    }
}

/// GET /dashboard/stats — the merchant's overview.
public struct DashboardStats: Codable, Sendable, Equatable {
    public struct Metric: Codable, Sendable, Equatable {
        public var value: Int
        public var trend: Double?

        public init(value: Int, trend: Double?) {
            self.value = value
            self.trend = trend
        }

        enum CodingKeys: String, CodingKey { case value, trend }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            value = try c.flexibleIntIfPresent(.value) ?? 0
            trend = try c.flexibleDoubleIfPresent(.trend)
        }
    }

    public struct Activity: Codable, Sendable, Equatable {
        public var type: String
        public var memberName: String?
        public var amount: Int?
        public var createdAt: String?

        enum CodingKeys: String, CodingKey {
            case type, amount
            case memberName = "member_name"
            case createdAt = "created_at"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
            memberName = try c.decodeIfPresent(String.self, forKey: .memberName)
            amount = try c.flexibleIntIfPresent(.amount)
            createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        }
    }

    public struct ChartPoint: Codable, Sendable, Equatable {
        public var date: String
        public var earnCount: Int
        public var redeemCount: Int

        enum CodingKeys: String, CodingKey {
            case date
            case earnCount = "earn_count"
            case redeemCount = "redeem_count"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
            earnCount = try c.flexibleIntIfPresent(.earnCount) ?? 0
            redeemCount = try c.flexibleIntIfPresent(.redeemCount) ?? 0
        }
    }

    public var period: String
    public var customers: Metric
    public var newCustomers: Metric
    public var transactions: Metric
    public var redemptions: Metric
    public var totalVehicles: Int?
    public var activityChart: [ChartPoint]
    public var recentActivities: [Activity]

    enum CodingKeys: String, CodingKey {
        case period, customers, transactions, redemptions
        case newCustomers = "new_customers"
        case totalVehicles = "total_vehicles"
        case activityChart = "activity_chart"
        case recentActivities = "recent_activities"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        period = try c.decodeIfPresent(String.self, forKey: .period) ?? "today"
        customers = try c.decode(Metric.self, forKey: .customers)
        newCustomers = try c.decode(Metric.self, forKey: .newCustomers)
        transactions = try c.decode(Metric.self, forKey: .transactions)
        redemptions = try c.decode(Metric.self, forKey: .redemptions)
        totalVehicles = try c.flexibleIntIfPresent(.totalVehicles)
        activityChart = try c.decodeIfPresent([ChartPoint].self, forKey: .activityChart) ?? []
        recentActivities = try c.decodeIfPresent([Activity].self, forKey: .recentActivities) ?? []
    }
}

/// GET /dashboard/platform-stats — the super admin's whole-platform overview.
public struct PlatformStats: Decodable, Sendable, Equatable {
    public struct TopShop: Decodable, Sendable, Equatable {
        public var id: Int
        public var name: String
        public var transactionsCount: Int

        enum CodingKeys: String, CodingKey {
            case id, name
            case transactionsCount = "transactions_count"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.flexibleInt(.id)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? "—"
            transactionsCount = try c.flexibleIntIfPresent(.transactionsCount) ?? 0
        }
    }

    public var shops: DashboardStats.Metric
    public var customers: DashboardStats.Metric
    public var transactions: DashboardStats.Metric
    public var activeSubscriptions: DashboardStats.Metric
    public var topActiveShops: [TopShop]

    enum CodingKeys: String, CodingKey {
        case shops, customers, transactions
        case activeSubscriptions = "active_subscriptions"
        case topActiveShops = "top_active_shops"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shops = try c.decode(DashboardStats.Metric.self, forKey: .shops)
        customers = try c.decode(DashboardStats.Metric.self, forKey: .customers)
        transactions = try c.decode(DashboardStats.Metric.self, forKey: .transactions)
        activeSubscriptions = try c.decode(DashboardStats.Metric.self, forKey: .activeSubscriptions)
        topActiveShops = try c.decodeIfPresent([TopShop].self, forKey: .topActiveShops) ?? []
    }
}

/// Customers of a shop holding its Apple Wallet card, and the devices
/// registered for that card's updates — the audience of a store message.
public struct WalletReach: Codable, Sendable, Equatable {
    public var cards: Int
    public var devices: Int

    public init(cards: Int, devices: Int) {
        self.cards = cards
        self.devices = devices
    }

    enum CodingKeys: String, CodingKey { case cards, devices }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cards = try c.flexibleIntIfPresent(.cards) ?? 0
        devices = try c.flexibleIntIfPresent(.devices) ?? 0
    }
}
