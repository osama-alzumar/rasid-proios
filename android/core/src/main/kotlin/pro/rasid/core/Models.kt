package pro.rasid.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull

// Mirrors of the Laravel API resources. Laravel/MySQL send decimals as
// strings ("15.00") and sometimes integers as strings, so values are read
// leniently from JsonObject instead of relying on strict decoding. The
// @Serializable classes are only used for the app's own offline store.

internal fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
internal fun JsonObject.int(key: String): Int? = str(key)?.trim()?.let { it.toIntOrNull() ?: it.toDoubleOrNull()?.toInt() }
internal fun JsonObject.double(key: String): Double? = (this[key] as? JsonPrimitive)?.let { if (it is JsonNull) null else it.doubleOrNull ?: it.contentOrNull?.trim()?.toDoubleOrNull() }
internal fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.let { if (it is JsonNull) null else it.booleanOrNull ?: it.contentOrNull?.let { c -> c == "1" || c == "true" } }
internal fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject
internal fun JsonObject.arr(key: String): List<JsonObject> = (this[key] as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList()
internal fun JsonElement?.asObj(): JsonObject? = this as? JsonObject

@Serializable
enum class RewardType { POINTS, STAMPS, VISITS;
    companion object {
        fun of(raw: String?) = when (raw) { "stamps" -> STAMPS; "visits" -> VISITS; else -> POINTS }
    }
}

@Serializable
enum class Role { CASHIER, SHOP_MANAGER, SUPER_ADMIN, MARKETER, UNKNOWN;
    companion object {
        fun of(raw: String?) = when (raw) {
            "cashier" -> CASHIER; "shop_manager" -> SHOP_MANAGER; "super_admin" -> SUPER_ADMIN; "marketer" -> MARKETER; else -> UNKNOWN
        }
    }
}

@Serializable
data class User(
    val id: Int,
    val name: String,
    val email: String,
    val shopId: Int? = null,
    val role: Role = Role.UNKNOWN,
    val permissions: List<String> = emptyList(),
) {
    fun can(permission: String) = role == Role.SUPER_ADMIN || permission in permissions
    val canCreateTransactions get() = can("transactions.create")
    val canCreateMembers get() = can("members.create")
    val canCreateVehicles get() = can("vehicles.create")
    val isManager get() = role == Role.SHOP_MANAGER
    val isSuperAdmin get() = role == Role.SUPER_ADMIN

    companion object {
        fun from(o: JsonObject) = User(
            id = o.int("id") ?: 0,
            name = o.str("name").orEmpty(),
            email = o.str("email").orEmpty(),
            shopId = o.int("shop_id"),
            role = Role.of(o.str("role")),
            permissions = (o["permissions"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: emptyList(),
        )
    }
}

@Serializable
data class Shop(
    val id: Int,
    val name: String,
    val rewardType: RewardType = RewardType.POINTS,
    val numberOfStamps: Int? = null,
    val minStampAmount: Double? = null,
    val initialPoints: Int? = null,
    val storeMessage: String? = null,
    val pointsPerAmount: Double = 1.0,
    val vehicleModuleEnabled: Boolean = false,
    val expiresAt: String? = null,
    val isExpired: Boolean = false,
    val membersCount: Int? = null,
) {
    /** Stamps needed for one reward (the server treats 0/null as 1). */
    val stampsPerReward get() = maxOf(numberOfStamps ?: 1, 1)

    companion object {
        fun from(o: JsonObject) = Shop(
            id = o.int("id") ?: 0,
            name = o.str("name").orEmpty(),
            rewardType = RewardType.of(o.str("reward_type")),
            numberOfStamps = o.int("number_of_stamps"),
            minStampAmount = o.double("min_stamp_amount"),
            initialPoints = o.int("initial_points"),
            storeMessage = o.str("store_message"),
            pointsPerAmount = o.double("points_per_amount") ?: 1.0,
            vehicleModuleEnabled = o.bool("vehicle_module_enabled") ?: false,
            expiresAt = o.str("expires_at"),
            isExpired = o.bool("is_expired") ?: false,
            membersCount = o.int("members_count"),
        )
    }
}

@Serializable
data class Service(val id: Int, val name: String, val price: Double? = null, val isActive: Boolean = true) {
    companion object {
        fun from(o: JsonObject) = Service(o.int("id") ?: 0, o.str("name").orEmpty(), o.double("price"), o.bool("is_active") ?: true)
    }
}

@Serializable
data class Vehicle(
    val id: Int,
    val memberId: Int,
    val plateLettersAr: String? = null,
    val plateNumber: String? = null,
    val plateDisplayAr: String? = null,
    val make: String? = null,
    val model: String? = null,
    val color: String? = null,
) {
    val plateText get() = plateDisplayAr?.takeIf { it.isNotBlank() } ?: listOfNotNull(plateLettersAr, plateNumber).joinToString(" ")
    val descriptionText get() = listOfNotNull(make, model, color).filter { it.isNotBlank() }.joinToString(" · ")

    companion object {
        /** Null for soft-deleted vehicles. */
        fun from(o: JsonObject): Vehicle? = if (o.str("deleted_at") != null) null else Vehicle(
            id = o.int("id") ?: 0, memberId = o.int("member_id") ?: 0,
            plateLettersAr = o.str("plate_letters_ar"), plateNumber = o.str("plate_number"), plateDisplayAr = o.str("plate_display_ar"),
            make = o.str("make"), model = o.str("model"), color = o.str("color"),
        )
    }
}

@Serializable
data class Member(
    val id: Int,
    val shopId: Int,
    val name: String,
    val phone: String? = null,
    val externalId: String? = null,
    val passkitId: String? = null,
    /** Balance as last confirmed by the server; pending ops are added on top by Snapshot. */
    val currentBalance: Int = 0,
    val redeemCount: Int = 0,
    val vehicles: List<Vehicle> = emptyList(),
    val createdAt: String? = null,
) {
    companion object {
        fun from(o: JsonObject) = Member(
            id = o.int("id") ?: 0, shopId = o.int("shop_id") ?: 0, name = o.str("name").orEmpty(),
            phone = o.str("phone"), externalId = o.str("external_id"), passkitId = o.str("passkit_id"),
            currentBalance = o.int("current_balance") ?: 0, redeemCount = o.int("redeem_count") ?: 0,
            vehicles = o.arr("vehicles").mapNotNull(Vehicle::from), createdAt = o.str("created_at"),
        )
    }
}

@Serializable
enum class TxType { EARN, REDEEM;
    val raw get() = name.lowercase()
}

@Serializable
data class ServerTransaction(
    val id: Int,
    val memberId: Int,
    val memberName: String? = null,
    val serviceName: String? = null,
    val invoiceNo: String? = null,
    val amount: Double? = null,
    val pointsChange: Int = 0,
    val type: TxType = TxType.EARN,
    val createdBy: String? = null,
    val createdAt: String? = null,
    /** Server balance right after this transaction, when the response embedded the member. */
    val memberBalanceAfter: Int? = null,
) {
    companion object {
        fun from(o: JsonObject): ServerTransaction {
            val member = o.obj("member")?.let(Member::from)
            return ServerTransaction(
                id = o.int("id") ?: 0, memberId = o.int("member_id") ?: 0,
                memberName = member?.name ?: o.str("member_name"),
                serviceName = o.str("service_name"), invoiceNo = o.str("invoice_no"), amount = o.double("amount"),
                pointsChange = o.int("points_change") ?: 0,
                type = if (o.str("type") == "redeem") TxType.REDEEM else TxType.EARN,
                createdBy = o.str("created_by"), createdAt = o.str("created_at"),
                memberBalanceAfter = member?.currentBalance,
            )
        }
    }
}

@Serializable
data class WalletReach(val cards: Int, val devices: Int) {
    companion object {
        fun from(o: JsonObject?) = o?.let { WalletReach(it.int("cards") ?: 0, it.int("devices") ?: 0) }
    }
}

/** The shop's self-scan QR: customers scan it and get one stamp/point a day. */
data class SelfScanSettings(val enabled: Boolean, val available: Boolean, val dailyLimit: Int = 1, val url: String? = null, val posterUrl: String? = null) {
    companion object {
        fun from(o: JsonObject) = SelfScanSettings(o.bool("enabled") ?: false, o.bool("available") ?: true, o.int("daily_limit") ?: 1, o.str("url"), o.str("poster_url"))
    }
}

data class Metric(val value: Int, val trend: Double?) {
    companion object {
        fun from(o: JsonObject?) = Metric(o?.int("value") ?: 0, o?.double("trend"))
    }
}

data class DashboardStats(
    val customers: Metric, val newCustomers: Metric, val transactions: Metric, val redemptions: Metric,
    val chart: List<Pair<Int, Int>>, val recent: List<Activity>,
) {
    data class Activity(val type: String, val memberName: String?, val amount: Int?)

    companion object {
        fun from(o: JsonObject) = DashboardStats(
            customers = Metric.from(o.obj("customers")), newCustomers = Metric.from(o.obj("new_customers")),
            transactions = Metric.from(o.obj("transactions")), redemptions = Metric.from(o.obj("redemptions")),
            chart = o.arr("activity_chart").map { (it.int("earn_count") ?: 0) to (it.int("redeem_count") ?: 0) },
            recent = o.arr("recent_activities").map { Activity(it.str("type").orEmpty(), it.str("member_name"), it.int("amount")) },
        )
    }
}

data class PlatformStats(val shops: Metric, val customers: Metric, val transactions: Metric, val activeSubscriptions: Metric, val topShops: List<Pair<String, Int>>) {
    companion object {
        fun from(o: JsonObject) = PlatformStats(
            Metric.from(o.obj("shops")), Metric.from(o.obj("customers")), Metric.from(o.obj("transactions")), Metric.from(o.obj("active_subscriptions")),
            o.arr("top_active_shops").map { (it.str("name") ?: "—") to (it.int("transactions_count") ?: 0) },
        )
    }
}

/** A platform announcement (GET /system-messages/pending). */
data class SystemMessage(val id: Int, val title: String, val body: String, val tone: Tone, val isForced: Boolean) {
    enum class Tone { INFO, SUCCESS, WARNING, DANGER }

    companion object {
        fun from(o: JsonObject): SystemMessage {
            val type = o.str("type")
            val tone = when (o.str("tone")) {
                "success" -> Tone.SUCCESS; "warning" -> Tone.WARNING; "danger" -> Tone.DANGER; "info" -> Tone.INFO
                else -> when (type) { "urgent" -> Tone.DANGER; "warning" -> Tone.WARNING; else -> Tone.INFO }
            }
            return SystemMessage(o.int("id") ?: 0, o.str("title").orEmpty(), o.str("body").orEmpty(), tone, o.bool("is_forced") ?: false)
        }
    }
}
