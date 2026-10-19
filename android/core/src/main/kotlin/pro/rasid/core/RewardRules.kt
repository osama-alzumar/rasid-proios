package pro.rasid.core

import kotlinx.serialization.Serializable
import kotlin.math.floor
import kotlin.math.min

/** What the cashier filled in for one earn/redeem operation. */
@Serializable
data class TransactionDraft(
    val memberId: Int,
    val type: TxType,
    val amount: Double? = null,
    /** Points to redeem (points shops) or stamps/visits to add on earn. */
    val count: Int? = null,
    val invoiceNo: String? = null,
    val vehicleId: Int? = null,
    val serviceId: Int? = null,
    /** Added by scanning the card with quick scan on: one stamp, no invoice. */
    val quickScan: Boolean? = null,
)

sealed class RuleError(val message: String) {
    data object AmountRequired : RuleError("أدخل قيمة الفاتورة.")
    data object InvoiceRequired : RuleError("أدخل رقم الفاتورة.")
    data object CountRequired : RuleError("أدخل العدد.")
    data class BelowMinimumStampAmount(val min: Double) : RuleError("الحد الأدنى لاحتساب الختم هو ${Formatting.amount(min)} ريال — قيمة الفاتورة المدخلة أقل من ذلك.")
    data class InsufficientBalance(val needed: Int, val available: Int) : RuleError("الرصيد غير كافٍ: المطلوب $needed والمتاح $available.")
    data object CardFull : RuleError("البطاقة مكتملة — المكافأة جاهزة للاستبدال.")
}

class RuleException(val error: RuleError) : Exception(error.message)

/**
 * Local mirror of the server's RewardStrategy classes and StoreTransactionRequest
 * rules, so an operation recorded offline is validated and counted exactly as
 * the server will count it.
 */
object RewardRules {
    data class FormSpec(
        val showsAmount: Boolean, val amountRequired: Boolean,
        val showsInvoice: Boolean, val invoiceRequired: Boolean,
        val showsCount: Boolean, val countRequired: Boolean,
    )

    fun formSpec(shop: Shop, type: TxType, hasService: Boolean): FormSpec = when (shop.rewardType) {
        RewardType.POINTS -> if (type == TxType.EARN)
            FormSpec(!hasService, !hasService, true, !hasService, false, false)
        else FormSpec(false, false, false, false, true, true)
        RewardType.STAMPS -> if (type == TxType.EARN) {
            val needsAmount = shop.minStampAmount != null
            FormSpec(needsAmount, needsAmount, true, !hasService, true, false)
        } else FormSpec(false, false, false, false, false, false)
        RewardType.VISITS -> if (type == TxType.EARN)
            FormSpec(false, false, true, false, !hasService, !hasService)
        else FormSpec(false, false, false, false, false, false)
    }

    /** Quick scan adds a stamp the moment a card is scanned: plain stamps shops only. */
    fun supportsQuickScan(shop: Shop): Boolean = shop.rewardType == RewardType.STAMPS && shop.minStampAmount == null

    sealed class QuickScan {
        /** Add one stamp now. */
        data class Add(val draft: TransactionDraft) : QuickScan()
        /** The card is full: the visit is the reward, open the member to redeem. */
        data object RewardReady : QuickScan()
        /** Quick scan does not apply: open the member as usual. */
        data object NotSupported : QuickScan()
    }

    fun quickScan(memberId: Int, shop: Shop, balance: Int): QuickScan = when {
        !supportsQuickScan(shop) -> QuickScan.NotSupported
        balance >= shop.stampsPerReward -> QuickScan.RewardReady
        else -> QuickScan.Add(TransactionDraft(memberId, TxType.EARN, count = 1, quickScan = true))
    }

    /** Validates the draft; returns the absolute balance change (the server's points_change). */
    fun evaluate(draft: TransactionDraft, shop: Shop, balance: Int, service: Service?): Result<Int> {
        var amount = draft.amount
        var count = draft.count
        val invoice = draft.invoiceNo?.trim().orEmpty()
        val hasService = service != null
        if (draft.type == TxType.EARN && service != null) {
            if (amount == null && service.price != null) amount = service.price
            if (count == null) count = 1
        }
        fun fail(e: RuleError) = Result.failure<Int>(RuleException(e))
        if (draft.quickScan == true) {
            if (draft.type != TxType.EARN || !supportsQuickScan(shop)) return fail(RuleError.InvoiceRequired)
            return if (balance >= shop.stampsPerReward) fail(RuleError.CardFull) else Result.success(1)
        }
        val spec = formSpec(shop, draft.type, hasService)
        if (spec.amountRequired && amount == null) return fail(RuleError.AmountRequired)
        if (spec.invoiceRequired && invoice.isEmpty()) return fail(RuleError.InvoiceRequired)
        if (spec.countRequired && (count ?: 0) < 1) return fail(RuleError.CountRequired)

        return when (shop.rewardType) {
            RewardType.POINTS -> if (draft.type == TxType.EARN) Result.success(floor((amount ?: 0.0) * shop.pointsPerAmount).toInt())
            else (count ?: 0).let { if (balance < it) fail(RuleError.InsufficientBalance(it, balance)) else Result.success(it) }
            RewardType.STAMPS -> if (draft.type == TxType.EARN) {
                val minAmount = shop.minStampAmount
                if (minAmount != null && (amount ?: -1.0) < minAmount) fail(RuleError.BelowMinimumStampAmount(minAmount))
                else Result.success(maxOf(1, count ?: 1))
            } else shop.stampsPerReward.let { if (balance < it) fail(RuleError.InsufficientBalance(it, balance)) else Result.success(it) }
            RewardType.VISITS -> if (draft.type == TxType.EARN) Result.success(count ?: 0)
            else if (balance < 1) fail(RuleError.InsufficientBalance(1, balance)) else Result.success(1)
        }
    }

    /** Body of POST /transactions, carrying the idempotency key. */
    fun requestBody(draft: TransactionDraft, clientUuid: String): Map<String, Any> = buildMap {
        put("member_id", draft.memberId)
        put("type", draft.type.raw)
        put("client_uuid", clientUuid.lowercase())
        draft.amount?.let { put("amount", it) }
        draft.count?.let { put("points_change", it) }
        draft.invoiceNo?.trim()?.takeIf { it.isNotEmpty() }?.let { put("invoice_no", it) }
        draft.vehicleId?.let { put("vehicle_id", it) }
        draft.serviceId?.let { put("service_id", it) }
        if (draft.quickScan == true) put("quick_scan", true)
    }
}

/** What a member's balance means for the shop's reward type, for display. */
data class BalanceSummary(val headline: String, val unit: String, val detail: String?, val filled: Int?, val total: Int?, val rewardAvailable: Boolean) {
    companion object {
        fun of(shop: Shop, balance: Int): BalanceSummary = when (shop.rewardType) {
            RewardType.POINTS -> BalanceSummary("$balance", "نقطة", null, null, null, balance > 0)
            RewardType.STAMPS -> {
                val total = shop.stampsPerReward
                val current = min(maxOf(balance, 0), total)
                val ready = balance >= total
                BalanceSummary("$current / $total", "ختم", if (ready) "المكافأة جاهزة للاستبدال" else "باقي ${total - current} للمكافأة", current, total, ready)
            }
            RewardType.VISITS -> BalanceSummary("$balance", "زيارة متبقية", if (balance > 0) null else "لا يوجد رصيد زيارات", null, null, balance > 0)
        }
    }
}

object Formatting {
    fun amount(value: Double): String = if (value == floor(value)) value.toLong().toString() else "%.2f".format(value)
}
