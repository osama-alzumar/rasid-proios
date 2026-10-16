package pro.rasid.core

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File
import java.io.IOException
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** In-memory stand-in for the Laravel API implementing TransactionController's rules (incl. client_uuid idempotency). */
class FakeServer(var shop: Shop, initial: List<Member>) : HttpTransport {
    val members = initial.associateBy { it.id }.toMutableMap()
    val updatedAt = initial.associate { it.id to 1000 }.toMutableMap()
    var clock = 1000
    val transactions = mutableListOf<Pair<String?, ServerTransaction>>()
    var online = true
    var dropNextResponse = false
    var role = "cashier"
    var expiredShop = false
    val requests = mutableListOf<String>()
    val shopIdsSeen = mutableListOf<String?>()
    var storeMessage: String? = null
    val acknowledged = mutableListOf<Int>()

    override fun send(method: String, url: String, headers: Map<String, String>, body: String?, timeoutSeconds: Long): Pair<Int, String> {
        if (!online) throw IOException("offline")
        val path = url.removePrefix(ApiClient.PRODUCTION).substringBefore("?")
        val query = url.substringAfter("?", "").split("&").filter { it.isNotEmpty() }.associate { it.substringBefore("=") to java.net.URLDecoder.decode(it.substringAfter("="), "UTF-8") }
        requests += "$method $path"
        val json = body?.let { Json.parseToJsonElement(it) as JsonObject }
        if (expiredShop) return 403 to """{"success":false,"shop_expired":true,"message":"انتهى اشتراك المحل"}"""
        if (path != "login" && headers["Authorization"] != "Bearer good-token") return 401 to """{"message":"Unauthenticated."}"""
        if (path.startsWith("app/")) shopIdsSeen += query["shop_id"]
        if (role == "super_admin" && path.startsWith("app/") && path != "app/bootstrap" && query["shop_id"] == null) return 422 to """{"message":"The shop id field is required."}"""

        return when ("$method $path") {
            "POST login" -> if (json!!.str("password") == "secret") 200 to obj("success" to true, "data" to buildJsonObject { put("user", userJson()); put("token", "good-token") })
                else 401 to """{"success":false,"message":"بيانات الدخول غير صحيحة"}"""
            "GET app/bootstrap" -> {
                val noShop = role == "super_admin" && query["shop_id"] == null
                200 to obj("success" to true, "data" to buildJsonObject {
                    put("server_time", "t$clock"); put("user", userJson()); put("shop", if (noShop) JsonNull else shopJson())
                    put("services", buildJsonArray { add(buildJsonObject { put("id", 7); put("name", "غسيل"); put("price", "25.00"); put("is_active", true) }) })
                    put("wallet_reach", if (noShop) JsonNull else buildJsonObject { put("cards", "3"); put("devices", 5) })
                })
            }
            "GET app/members" -> {
                val since = query["since"]?.drop(1)?.toInt()
                val afterId = query["after_id"]?.toInt() ?: 0
                val filtered = members.values.filter { it.id > afterId && (since == null || updatedAt[it.id]!! > since) }.sortedBy { it.id }
                val page = filtered.take(2)
                val more = filtered.size > 2
                200 to obj("success" to true, "data" to JsonArray(page.map(::memberJson)), "meta" to buildJsonObject {
                    put("server_time", "t$clock"); put("has_more", more); put("next_after_id", if (more) JsonPrimitive(page.last().id) else JsonNull)
                    put("all_ids", if (afterId == 0) JsonArray(members.keys.sorted().map { JsonPrimitive(it) }) else JsonNull)
                })
            }
            "GET app/transactions" -> 200 to obj("success" to true, "data" to JsonArray(transactions.reversed().map { txJson(it.second) }))
            "POST transactions" -> {
                val uuid = json!!.str("client_uuid")
                transactions.firstOrNull { it.first != null && it.first == uuid }?.let { return 200 to obj("success" to true, "already_applied" to true, "data" to txJson(it.second)) }
                val memberId = json.int("member_id")!!
                val member = members[memberId] ?: return 422 to """{"message":"The selected member id is invalid."}"""
                val type = if (json.str("type") == "redeem") TxType.REDEEM else TxType.EARN
                val draft = TransactionDraft(memberId, type, json.double("amount"), json.int("points_change"), json.str("invoice_no"), serviceId = json.int("service_id"))
                val service = if (draft.serviceId == 7) Service(7, "غسيل", 25.0) else null
                RewardRules.evaluate(draft, shop, member.currentBalance, service).fold({ change ->
                    members[memberId] = member.copy(currentBalance = member.currentBalance + if (type == TxType.EARN) change else -change)
                    clock++; updatedAt[memberId] = clock
                    val tx = ServerTransaction(transactions.size + 1, memberId, member.name, pointsChange = change, type = type, createdBy = "كاشير")
                    transactions += uuid to tx
                    if (dropNextResponse) { dropNextResponse = false; throw IOException("lost") }
                    201 to obj("success" to true, "data" to txJson(tx))
                }, { 422 to obj("success" to false, "message" to (it as RuleException).error.message) })
            }
            "POST shops/${shop.id}/push-message" -> when {
                role == "cashier" -> 403 to """{"message":"لا تملك صلاحية إرسال رسائل لعملاء هذا المحل."}"""
                json!!.str("message").isNullOrEmpty() -> 422 to """{"message":"The given data was invalid.","errors":{"message":["الرسالة مطلوبة."]}}"""
                else -> { storeMessage = json.str("message"); 200 to """{"success":true,"reach":{"cards":3,"devices":5}}""" }
            }
            "GET system-messages/pending" -> 200 to """{"success":true,"data":[{"id":10,"title":"صيانة","body":"توقف مؤقت","type":"urgent","tone":"success","is_forced":true},{"id":11,"title":"ميزة","body":"جديد","type":"warning","tone":null,"is_forced":false}]}"""
            "POST system-messages/10/ack" -> { acknowledged += 10; 200 to """{"success":true}""" }
            else -> 404 to """{"message":"Not found"}"""
        }
    }

    private fun obj(vararg pairs: Pair<String, Any>) = buildJsonObject {
        pairs.forEach { (k, v) -> when (v) { is Boolean -> put(k, v); is String -> put(k, v); is kotlinx.serialization.json.JsonElement -> put(k, v) } }
    }.toString()

    private fun userJson() = buildJsonObject {
        put("id", 1); put("name", "كاشير"); put("email", "c@x.com"); put("role", role)
        put("shop_id", if (role == "super_admin") JsonNull else JsonPrimitive(shop.id))
        put("permissions", if (role == "super_admin") JsonArray(emptyList()) else JsonArray(listOf("members.view-any", "members.create", "transactions.create").map { JsonPrimitive(it) }))
    }

    private fun shopJson() = buildJsonObject {
        put("id", shop.id); put("name", shop.name); put("reward_type", shop.rewardType.name.lowercase())
        put("number_of_stamps", shop.numberOfStamps ?: 0); put("points_per_amount", "${shop.pointsPerAmount}"); put("is_expired", false)
        shop.minStampAmount?.let { put("min_stamp_amount", "%.2f".format(it)) }
    }

    fun memberJson(m: Member) = buildJsonObject {
        put("id", m.id); put("shop_id", m.shopId); put("name", m.name); put("phone", m.phone); put("external_id", m.externalId)
        put("current_balance", m.currentBalance); put("redeem_count", m.redeemCount); put("vehicles", JsonArray(emptyList())); put("created_at", "2026-10-01 10:00:00")
    }

    private fun txJson(t: ServerTransaction) = buildJsonObject {
        put("id", t.id); put("member_id", t.memberId); put("points_change", t.pointsChange); put("type", t.type.raw); put("created_by", t.createdBy)
        put("member", memberJson(members[t.memberId]!!))
    }
}

class RewardRulesTest {
    private val points = Shop(1, "قهوة", RewardType.POINTS, pointsPerAmount = 0.5)
    private val stamps = Shop(1, "قهوة", RewardType.STAMPS, numberOfStamps = 6)
    private val minStamp = Shop(1, "قهوة", RewardType.STAMPS, numberOfStamps = 5, minStampAmount = 15.0)
    private val visits = Shop(1, "مغسلة", RewardType.VISITS, initialPoints = 10)
    private fun err(r: Result<Int>) = (r.exceptionOrNull() as RuleException).error

    @Test fun pointsEarnScalesAndRoundsDown() = assertEquals(18, RewardRules.evaluate(TransactionDraft(1, TxType.EARN, 37.0, invoiceNo = "A1"), points, 0, null).getOrThrow())
    @Test fun pointsNeedAmountAndInvoice() {
        assertEquals(RuleError.AmountRequired, err(RewardRules.evaluate(TransactionDraft(1, TxType.EARN, invoiceNo = "A"), points, 0, null)))
        assertEquals(RuleError.InvoiceRequired, err(RewardRules.evaluate(TransactionDraft(1, TxType.EARN, 10.0, invoiceNo = "  "), points, 0, null)))
    }
    @Test fun serviceSuppliesPrice() = assertEquals(20, RewardRules.evaluate(TransactionDraft(1, TxType.EARN, serviceId = 7), points, 0, Service(7, "غسيل", 40.0)).getOrThrow())
    @Test fun pointsRedeemChecksBalance() {
        assertEquals(RuleError.InsufficientBalance(50, 49), err(RewardRules.evaluate(TransactionDraft(1, TxType.REDEEM, count = 50), points, 49, null)))
        assertEquals(50, RewardRules.evaluate(TransactionDraft(1, TxType.REDEEM, count = 50), points, 50, null).getOrThrow())
    }
    @Test fun stamps() {
        assertEquals(1, RewardRules.evaluate(TransactionDraft(1, TxType.EARN, invoiceNo = "A"), stamps, 0, null).getOrThrow())
        assertEquals(RuleError.BelowMinimumStampAmount(15.0), err(RewardRules.evaluate(TransactionDraft(1, TxType.EARN, 14.99, invoiceNo = "A"), minStamp, 0, null)))
        assertEquals(RuleError.InsufficientBalance(6, 5), err(RewardRules.evaluate(TransactionDraft(1, TxType.REDEEM), stamps, 5, null)))
        assertEquals(6, RewardRules.evaluate(TransactionDraft(1, TxType.REDEEM), stamps, 7, null).getOrThrow())
    }
    @Test fun visits() {
        assertEquals(RuleError.CountRequired, err(RewardRules.evaluate(TransactionDraft(1, TxType.EARN), visits, 0, null)))
        assertEquals(1, RewardRules.evaluate(TransactionDraft(1, TxType.EARN, serviceId = 7), visits, 0, Service(7, "غسيل", null)).getOrThrow())
        assertEquals(1, RewardRules.evaluate(TransactionDraft(1, TxType.REDEEM), visits, 3, null).getOrThrow())
    }
    @Test fun balanceSummary() {
        assertEquals("4 / 6", BalanceSummary.of(stamps, 4).headline)
        assertTrue(BalanceSummary.of(stamps, 6).rewardAvailable)
    }
    @Test fun lenientDecoding() {
        val shop = Shop.from(Json.parseToJsonElement("""{"id":"5","name":"م","reward_type":"stamps","number_of_stamps":"6","min_stamp_amount":"15.00","points_per_amount":"1.50"}""") as JsonObject)
        assertEquals(5, shop.id); assertEquals(6, shop.numberOfStamps); assertEquals(15.0, shop.minStampAmount); assertEquals(1.5, shop.pointsPerAmount)
        val member = Member.from(Json.parseToJsonElement("""{"id":1,"shop_id":2,"name":"ع","current_balance":"12","vehicles":[{"id":1,"member_id":1,"plate_number":"123","deleted_at":null},{"id":2,"member_id":1,"deleted_at":"2026-01-01"}]}""") as JsonObject)
        assertEquals(12, member.currentBalance); assertEquals(listOf(1), member.vehicles.map { it.id })
        assertEquals(ApiError.Rejected(422, "رقم الهاتف مستخدم"), mapError(422, """{"message":"x","errors":{"phone":["رقم الهاتف مستخدم"]}}"""))
        assertTrue(mapError(502, "<html>").isTransient)
    }
}

class SyncTest {
    private fun server(type: RewardType = RewardType.POINTS) = FakeServer(Shop(9, "محل", type, numberOfStamps = 6), listOf(
        Member(1, 9, "سارة", "0551112222", "EXT_000001", currentBalance = 100),
        Member(2, 9, "خالد", "0553334444", "EXT_000002", currentBalance = 0),
        Member(3, 9, "منى", "0555556666", "EXT_000003", currentBalance = 6),
    ))
    private fun engine(s: FakeServer, file: File? = null) = LocalStore(file).let { it to SyncEngine(it, ApiClient("good-token", s)) }

    @Test fun loginAndWrongPassword() = runTest {
        val s = server(); val api = ApiClient(transport = s)
        assertEquals("good-token", api.login("c@x.com", "secret").token)
        assertEquals(ApiError.Rejected(401, "البريد الإلكتروني أو كلمة المرور غير صحيحة."), assertFailsWith<ApiError> { api.login("c@x.com", "bad") })
    }

    @Test fun pagedDownloadAndSearch() = runTest {
        val s = server(); val (store, e) = engine(s)
        assertEquals(3, e.sync().membersUpdated)
        assertEquals(2, s.requests.count { it == "GET app/members" })
        assertEquals(1, store.findMember("٠٥٥١١١٢٢٢٢")?.id)
        assertEquals(3, store.findMember("ext_000003")?.id)
        assertEquals(listOf(2), store.searchMembers("خالد").map { it.id })
        assertEquals(WalletReach(3, 5), store.snapshot.walletReach)
    }

    @Test fun offlineQueueSyncsLater() = runTest {
        val s = server(); val (store, e) = engine(s)
        e.sync(); s.online = false
        store.enqueue(TransactionDraft(1, TxType.REDEEM, count = 30))
        store.enqueue(TransactionDraft(2, TxType.EARN, 40.0, invoiceNo = "F-9"))
        assertEquals(70, store.snapshot.displayBalance(1)); assertEquals(40, store.snapshot.displayBalance(2))
        assertTrue(e.sync().offline)
        assertEquals(2, store.pendingOperations.size)
        s.online = true
        assertEquals(2, e.sync().sent)
        assertEquals(70, s.members[1]!!.currentBalance); assertEquals(40, s.members[2]!!.currentBalance)
        assertEquals(0, store.pendingOperations.size); assertEquals(70, store.snapshot.displayBalance(1))
    }

    @Test fun lostResponseNotAppliedTwice() = runTest {
        val s = server(); val (store, e) = engine(s)
        e.sync()
        store.enqueue(TransactionDraft(2, TxType.EARN, 10.0, invoiceNo = "X"))
        s.dropNextResponse = true
        assertTrue(e.sync().offline)
        assertEquals(10, store.snapshot.displayBalance(2))
        assertEquals(1, e.sync().sent)
        assertEquals(1, s.transactions.size); assertEquals(10, s.members[2]!!.currentBalance); assertEquals(10, store.snapshot.displayBalance(2))
    }

    @Test fun rejectionStopsCounting() = runTest {
        val s = server(); val (store, e) = engine(s)
        e.sync(); s.online = false
        store.enqueue(TransactionDraft(1, TxType.REDEEM, count = 80))
        s.online = true; s.members[1] = s.members[1]!!.copy(currentBalance = 50); s.clock++; s.updatedAt[1] = s.clock
        assertEquals(1, e.sync().rejected)
        assertTrue(store.snapshot.pending.first().rejected)
        assertEquals(50, store.snapshot.displayBalance(1))
    }

    @Test fun localValidationBlocksOverRedeem() = runTest {
        val s = server(RewardType.STAMPS); val (store, e) = engine(s)
        e.sync(); s.online = false
        store.enqueue(TransactionDraft(3, TxType.REDEEM))
        val ex = assertFailsWith<RuleException> { store.enqueue(TransactionDraft(3, TxType.REDEEM)) }
        assertEquals(RuleError.InsufficientBalance(6, 0), ex.error)
    }

    @Test fun deltaAndDeletions() = runTest {
        val s = server(); val (store, e) = engine(s)
        e.sync()
        s.clock++; s.members[2] = s.members[2]!!.copy(currentBalance = 55); s.updatedAt[2] = s.clock; s.members.remove(3)
        assertEquals(1, e.sync().membersUpdated)
        assertEquals(55, store.snapshot.members[2]!!.currentBalance); assertNull(store.snapshot.members[3])
    }

    @Test fun persistsAcrossLaunches() = runTest {
        val dir = Files.createTempDirectory("rasid").toFile(); val f = File(dir, "store.json")
        val s = server(); val (store, e) = engine(s, f)
        e.sync(); s.online = false
        store.enqueue(TransactionDraft(2, TxType.EARN, 5.0, invoiceNo = "P"))
        val relaunched = LocalStore(f)
        assertEquals(3, relaunched.snapshot.members.size); assertEquals(1, relaunched.pendingOperations.size); assertEquals(5, relaunched.snapshot.displayBalance(2))
        dir.deleteRecursively()
    }

    @Test fun expiredShopKeepsQueue() = runTest {
        val s = server(); val (store, e) = engine(s)
        e.sync(); store.enqueue(TransactionDraft(2, TxType.EARN, 5.0, invoiceNo = "P"))
        s.expiredShop = true
        assertIs<ApiError.ShopExpired>(assertFailsWith<ApiError> { e.sync() })
        assertEquals(1, store.pendingOperations.size)
    }

    @Test fun superAdminPicksShop() = runTest {
        val s = server(); s.role = "super_admin"; val (store, e) = engine(s)
        assertTrue(!e.sync().offline)
        assertNull(store.snapshot.shop); assertTrue(store.snapshot.members.isEmpty())
        store.selectShop(s.shop)
        assertEquals(3, e.sync().membersUpdated)
        assertTrue(s.shopIdsSeen.takeLast(4).all { it == "9" })
        store.enqueue(TransactionDraft(2, TxType.EARN, 20.0, invoiceNo = "SA"))
        assertEquals(1, e.sync().sent)
    }

    @Test fun staffNeverSendShopId() = runTest {
        val s = server(); engine(s).second.sync()
        assertTrue(s.shopIdsSeen.all { it == null })
    }

    @Test fun cannotSwitchShopWithUnsentOps() = runTest {
        val s = server(); s.role = "super_admin"; val (store, e) = engine(s)
        store.selectShop(s.shop); e.sync(); s.online = false
        store.enqueue(TransactionDraft(1, TxType.REDEEM, count = 10))
        assertIs<ApiError.Rejected>(assertFailsWith<ApiError> { store.selectShop(Shop(10, "آخر")) })
    }

    @Test fun storeMessagesAndSystemMessages() = runTest {
        val s = server(); val api = ApiClient("good-token", s)
        assertEquals(ApiError.Rejected(403, "لا تملك صلاحية إرسال رسائل لعملاء هذا المحل."), assertFailsWith<ApiError> { api.sendStoreMessage(9, "عرض") })
        s.role = "shop_manager"
        assertEquals(WalletReach(3, 5), api.sendStoreMessage(9, "عرض اليوم")); assertEquals("عرض اليوم", s.storeMessage)
        assertEquals(ApiError.Rejected(422, "الرسالة مطلوبة."), assertFailsWith<ApiError> { api.sendStoreMessage(9, "") })
        val messages = api.pendingSystemMessages()
        assertContentEquals(listOf(10, 11), messages.map { it.id })
        assertEquals(SystemMessage.Tone.SUCCESS, messages[0].tone); assertTrue(messages[0].isForced)
        assertEquals(SystemMessage.Tone.WARNING, messages[1].tone)
        api.acknowledgeSystemMessage(10); assertEquals(listOf(10), s.acknowledged)
    }
}
