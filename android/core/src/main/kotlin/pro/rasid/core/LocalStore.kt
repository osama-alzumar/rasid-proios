package pro.rasid.core

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

/** An earn/redeem recorded on this device that the server has not confirmed yet. */
@Serializable
data class PendingOperation(
    val id: String = UUID.randomUUID().toString(),
    val draft: TransactionDraft,
    /** Balance change computed locally by RewardRules (always positive). */
    val pointsChange: Int,
    val memberName: String,
    val createdAtMillis: Long = System.currentTimeMillis(),
    val rejected: Boolean = false,
    val lastError: String? = null,
    val attempts: Int = 0,
) {
    /** Signed effect on the member's balance while still pending. */
    val signedDelta get() = if (rejected) 0 else if (draft.type == TxType.EARN) pointsChange else -pointsChange
}

/** Everything the app keeps on the device for one logged-in user. */
@Serializable
data class Snapshot(
    val user: User? = null,
    val shop: Shop? = null,
    val services: List<Service> = emptyList(),
    val walletReach: WalletReach? = null,
    val members: Map<Int, Member> = emptyMap(),
    val recentTransactions: List<ServerTransaction> = emptyList(),
    val pending: List<PendingOperation> = emptyList(),
    /** Server time of the last members download (cursor for deltas). */
    val membersSyncedAt: String? = null,
    val lastSuccessfulSyncMillis: Long? = null,
    /** Super admin only: the shop being worked on. */
    val selectedShopId: Int? = null,
) {
    /** Balance shown to the cashier: server balance plus pending local ops. */
    fun displayBalance(memberId: Int) = (members[memberId]?.currentBalance ?: 0) + pendingDelta(memberId)
    fun pendingDelta(memberId: Int) = pending.filter { it.draft.memberId == memberId }.sumOf { it.signedDelta }
    val pendingCount get() = pending.count { !it.rejected }
    val rejectedCount get() = pending.count { it.rejected }
}

/**
 * File-backed store for the offline copy. All mutations are serialized by a
 * mutex and written atomically (temp file + rename), so a crash never leaves a
 * half-written file.
 */
class LocalStore(private val file: File?) {
    private val mutex = Mutex()
    private val json = Json { ignoreUnknownKeys = true; allowStructuredMapKeys = true }

    @Volatile
    var snapshot: Snapshot = file?.takeIf { it.exists() }?.let { runCatching { json.decodeFromString<Snapshot>(it.readText()) }.getOrNull() } ?: Snapshot()
        private set

    private suspend fun mutate(change: (Snapshot) -> Snapshot) = mutex.withLock {
        snapshot = change(snapshot)
        save()
    }

    private fun save() {
        val f = file ?: return
        f.parentFile?.mkdirs()
        val tmp = File(f.parentFile, f.name + ".tmp")
        tmp.writeText(json.encodeToString(Snapshot.serializer(), snapshot))
        if (!tmp.renameTo(f)) { f.delete(); tmp.renameTo(f) }
    }

    // ---- reads ----

    /** Exact match on the codes a wallet pass / cashier may present. */
    fun findMember(code: String): Member? {
        val c = normalize(code)
        if (c.isEmpty()) return null
        return snapshot.members.values.firstOrNull { m -> listOfNotNull(m.externalId, m.phone, m.passkitId).any { normalize(it) == c } }
    }

    fun searchMembers(query: String, limit: Int = 200): List<Member> {
        val q = normalize(query)
        val all = snapshot.members.values
        val matches = if (q.isEmpty()) all.toList() else all.filter { m ->
            normalize(m.name).contains(q) || listOfNotNull(m.phone, m.externalId).any { normalize(it).contains(q) } ||
                m.vehicles.any { normalize(it.plateText).contains(q) || normalize(it.plateNumber.orEmpty()).contains(q) }
        }
        return matches.sortedWith(compareByDescending<Member> { it.createdAt.orEmpty() }.thenByDescending { it.id }).take(limit)
    }

    // ---- session ----

    suspend fun replaceSession(user: User) = mutate { Snapshot(user = user) }
    suspend fun clear() = mutex.withLock { snapshot = Snapshot(); file?.delete() }

    /** Super admin: switch shop. Refused while operations are unsent. */
    suspend fun selectShop(shop: Shop) = mutate {
        if (it.pendingCount > 0) throw ApiError.Rejected(409, "يوجد عمليات لم تُرسل بعد. انتظر المزامنة قبل تغيير المحل.")
        Snapshot(user = it.user, shop = shop, selectedShopId = shop.id)
    }

    // ---- server data ----

    suspend fun applyBootstrap(b: Bootstrap) = mutate { it.copy(user = b.user, shop = b.shop, services = b.services, walletReach = b.walletReach) }

    suspend fun applyMembersPage(page: MembersPage) = mutate { s ->
        var members = s.members
        page.allIds?.let { ids -> val keep = ids.toSet(); members = members.filterKeys { it in keep } }
        s.copy(members = members + page.members.associateBy { it.id })
    }

    suspend fun finishMembersSync(serverTime: String, now: Long = System.currentTimeMillis()) =
        mutate { it.copy(membersSyncedAt = serverTime, lastSuccessfulSyncMillis = now) }

    suspend fun upsertMember(member: Member) = mutate { it.copy(members = it.members + (member.id to member)) }

    suspend fun addVehicle(vehicle: Vehicle) = mutate { s ->
        val m = s.members[vehicle.memberId] ?: return@mutate s
        s.copy(members = s.members + (m.id to m.copy(vehicles = m.vehicles.filter { it.id != vehicle.id } + vehicle)))
    }

    suspend fun setRecentTransactions(list: List<ServerTransaction>) = mutate { it.copy(recentTransactions = list) }

    // ---- outbox ----

    /** Validates and queues an operation; the shown balance changes immediately. */
    suspend fun enqueue(draft: TransactionDraft): PendingOperation {
        var op: PendingOperation? = null
        mutate { s ->
            val shop = s.shop ?: throw RuleException(RuleError.CountRequired)
            val member = s.members[draft.memberId] ?: throw ApiError.Rejected(404, "العميل غير موجود على هذا الجهاز.")
            val service = draft.serviceId?.let { id -> s.services.firstOrNull { it.id == id } }
            val change = RewardRules.evaluate(draft, shop, s.displayBalance(draft.memberId), service).getOrThrow()
            op = PendingOperation(draft = draft, pointsChange = change, memberName = member.name)
            s.copy(pending = s.pending + op!!)
        }
        return op!!
    }

    val pendingOperations get() = snapshot.pending.filter { !it.rejected }

    /** The server applied it: drop from the outbox, adopt the server balance. */
    suspend fun confirm(id: String, result: TransactionResult) = mutate { s ->
        val op = s.pending.firstOrNull { it.id == id } ?: return@mutate s
        var members = s.members
        val after = result.transaction.memberBalanceAfter
        val m = members[op.draft.memberId]
        if (after != null && m != null) {
            members = members + (m.id to m.copy(currentBalance = after, redeemCount = m.redeemCount + if (op.draft.type == TxType.REDEEM && !result.alreadyApplied) 1 else 0))
        }
        val tx = result.transaction.let { if (it.memberName == null) it.copy(memberName = op.memberName) else it }
        s.copy(pending = s.pending.filter { it.id != id }, members = members,
            recentTransactions = (listOf(tx) + s.recentTransactions.filter { it.id != tx.id }).take(300))
    }

    suspend fun markRejected(id: String, message: String) = mutate { s ->
        s.copy(pending = s.pending.map { if (it.id == id) it.copy(rejected = true, lastError = message) else it })
    }

    suspend fun noteAttempt(id: String, error: String) = mutate { s ->
        s.copy(pending = s.pending.map { if (it.id == id) it.copy(attempts = it.attempts + 1, lastError = error) else it })
    }

    suspend fun discard(id: String) = mutate { s -> s.copy(pending = s.pending.filter { it.id != id }) }

    companion object {
        private val digits = mapOf('٠' to '0', '١' to '1', '٢' to '2', '٣' to '3', '٤' to '4', '٥' to '5', '٦' to '6', '٧' to '7', '٨' to '8', '٩' to '9',
            '۰' to '0', '۱' to '1', '۲' to '2', '۳' to '3', '۴' to '4', '۵' to '5', '۶' to '6', '۷' to '7', '۸' to '8', '۹' to '9')

        /** Case/space-insensitive, Arabic-Indic digits mapped to ASCII ("٠٥٥…" == "055…"). */
        fun normalize(s: String): String = buildString { s.lowercase().forEach { ch -> if (!ch.isWhitespace()) append(digits[ch] ?: ch) } }
    }
}
