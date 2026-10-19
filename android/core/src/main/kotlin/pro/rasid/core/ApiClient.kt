package pro.rasid.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

sealed class ApiError(override val message: String) : Exception(message) {
    /** No connection / timeout: retry later. */
    data object Offline : ApiError("لا يوجد اتصال بالخادم.")
    /** Token revoked: log in again. */
    data object Unauthorized : ApiError("انتهت الجلسة، سجّل الدخول من جديد.")
    data class AccountDisabled(val text: String) : ApiError(text)
    data class ShopExpired(val text: String) : ApiError(text)
    /** The server refused the request (validation / business rule). */
    data class Rejected(val status: Int, val text: String) : ApiError(text)
    data class Server(val status: Int) : ApiError("تعذر الاتصال بالخادم ($status). حاول لاحقاً.")

    val isTransient get() = this is Offline || this is Server
}

/** Minimal HTTP seam so the sync engine can be tested without a network. */
fun interface HttpTransport {
    /** Returns (status, body); throws IOException when the server is unreachable. */
    @Throws(IOException::class)
    fun send(method: String, url: String, headers: Map<String, String>, body: String?, timeoutSeconds: Long): Pair<Int, String>
}

class OkHttpTransport(private val client: OkHttpClient = OkHttpClient()) : HttpTransport {
    override fun send(method: String, url: String, headers: Map<String, String>, body: String?, timeoutSeconds: Long): Pair<Int, String> {
        val request = Request.Builder().url(url).apply {
            headers.forEach { (k, v) -> header(k, v) }
            method(method, body?.toRequestBody("application/json".toMediaType()))
        }.build()
        val call = client.newBuilder().callTimeout(timeoutSeconds, TimeUnit.SECONDS).build().newCall(request)
        call.execute().use { return it.code to (it.body?.string() ?: "") }
    }
}

data class LoginResult(val user: User, val token: String)
data class Bootstrap(val serverTime: String, val user: User, val shop: Shop?, val services: List<Service>, val walletReach: WalletReach?)
data class MembersPage(val members: List<Member>, val serverTime: String, val hasMore: Boolean, val nextAfterId: Int?, val allIds: List<Int>?)
data class TransactionResult(val transaction: ServerTransaction, val alreadyApplied: Boolean)

/** Client for the Laravel API at https://rasid.pro/backend/api. */
class ApiClient(
    private val token: String? = null,
    private val transport: HttpTransport = OkHttpTransport(),
    private val baseUrl: String = PRODUCTION,
) {
    companion object {
        const val PRODUCTION = "https://rasid.pro/backend/api/"
        private val json = Json { ignoreUnknownKeys = true }
    }

    fun withToken(token: String?) = ApiClient(token, transport, baseUrl)

    suspend fun login(email: String, password: String): LoginResult = try {
        // client=android: the server applies the app-only owner rule.
        val data = request("POST", "login", body = mapOf("email" to email, "password" to password, "client" to "android")).dataObj()
        LoginResult(User.from(data.obj("user")!!), data.str("token")!!)
    } catch (e: ApiError.Unauthorized) {
        throw ApiError.Rejected(401, "البريد الإلكتروني أو كلمة المرور غير صحيحة.")
    }

    suspend fun logout() { request("POST", "logout", body = emptyMap<String, Any>()) }

    suspend fun bootstrap(shopId: Int? = null): Bootstrap {
        val d = request("GET", "app/bootstrap", query = shopQuery(shopId)).dataObj()
        return Bootstrap(d.str("server_time").orEmpty(), User.from(d.obj("user")!!), d.obj("shop")?.let(Shop::from),
            d.arr("services").map(Service::from), WalletReach.from(d.obj("wallet_reach")))
    }

    suspend fun members(since: String?, afterId: Int, shopId: Int? = null): MembersPage {
        val q = mutableListOf("after_id" to afterId.toString()) + shopQuery(shopId) + listOfNotNull(since?.let { "since" to it })
        val root = request("GET", "app/members", query = q)
        val meta = root.obj("meta")!!
        return MembersPage(
            members = root.arr("data").map(Member::from),
            serverTime = meta.str("server_time").orEmpty(),
            hasMore = meta.bool("has_more") ?: false,
            nextAfterId = meta.int("next_after_id"),
            allIds = (meta["all_ids"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull?.toIntOrNull() },
        )
    }

    suspend fun recentTransactions(limit: Int = 100, shopId: Int? = null): List<ServerTransaction> =
        request("GET", "app/transactions", query = listOf("limit" to "$limit") + shopQuery(shopId)).arr("data").map(ServerTransaction::from)

    suspend fun lookupMember(code: String): Member =
        Member.from(request("GET", "members/lookup/" + URLEncoder.encode(code.trim(), "UTF-8").replace("+", "%20")).dataObj())

    suspend fun createMember(name: String, phone: String?, shopId: Int?): Member =
        Member.from(request("POST", "members", body = buildMap {
            put("name", name); phone?.takeIf { it.isNotBlank() }?.let { put("phone", it) }; shopId?.let { put("shop_id", it) }
        }).dataObj())

    suspend fun createVehicle(memberId: Int, lettersAr: String, number: String, make: String?, model: String?, color: String?): Vehicle =
        Vehicle.from(request("POST", "vehicles", body = buildMap {
            put("member_id", memberId); put("plate_letters_ar", lettersAr); put("plate_number", number)
            make?.takeIf { it.isNotBlank() }?.let { put("make", it) }; model?.takeIf { it.isNotBlank() }?.let { put("model", it) }
            color?.takeIf { it.isNotBlank() }?.let { put("color", it) }
        }).dataObj())!!

    suspend fun createTransaction(draft: TransactionDraft, clientUuid: String): TransactionResult {
        val root = request("POST", "transactions", body = RewardRules.requestBody(draft, clientUuid))
        return TransactionResult(ServerTransaction.from(root.obj("data")!!), root.bool("already_applied") ?: false)
    }

    suspend fun dashboardStats(period: String) = DashboardStats.from(request("GET", "dashboard/stats", query = listOf("period" to period)).dataObj())
    suspend fun platformStats(period: String) = PlatformStats.from(request("GET", "dashboard/platform-stats", query = listOf("period" to period)).dataObj())

    suspend fun shops(search: String): List<Shop> =
        request("GET", "shops", query = listOf("per_page" to "100") + listOfNotNull(search.takeIf { it.isNotBlank() }?.let { "search" to it })).arr("data").map(Shop::from)

    /** Sets the store message on every customer's Wallet card (re-signing can be slow). */
    suspend fun sendStoreMessage(shopId: Int, message: String): WalletReach? =
        WalletReach.from(request("POST", "shops/$shopId/push-message", body = mapOf("message" to message), timeout = 120).obj("reach"))

    suspend fun selfScan(shopId: Int): SelfScanSettings = SelfScanSettings.from(request("GET", "shops/$shopId/self-scan").obj("data") ?: JsonObject(emptyMap()))

    /** Turns the shop's self-scan QR on or off; newCode replaces the QR (the old one stops working). */
    suspend fun updateSelfScan(shopId: Int, enabled: Boolean, newCode: Boolean = false): SelfScanSettings =
        SelfScanSettings.from(request("PUT", "shops/$shopId/self-scan", body = buildMap { put("enabled", enabled); if (newCode) put("new_code", true) }).obj("data") ?: JsonObject(emptyMap()))

    suspend fun pendingSystemMessages(): List<SystemMessage> = request("GET", "system-messages/pending").arr("data").map(SystemMessage::from)
    suspend fun acknowledgeSystemMessage(id: Int) { request("POST", "system-messages/$id/ack", body = emptyMap<String, Any>()) }

    // ---- plumbing ----

    private fun shopQuery(shopId: Int?) = listOfNotNull(shopId?.let { "shop_id" to it.toString() })

    private fun JsonObject.dataObj(): JsonObject = obj("data") ?: throw ApiError.Server(200)

    private suspend fun request(method: String, path: String, query: List<Pair<String, String>> = emptyList(), body: Map<String, Any>? = null, timeout: Long = 20): JsonObject =
        withContext(Dispatchers.IO) {
            val qs = if (query.isEmpty()) "" else "?" + query.joinToString("&") { (k, v) -> "$k=" + URLEncoder.encode(v, "UTF-8") }
            val headers = buildMap {
                put("Accept", "application/json"); put("Accept-Language", "ar")
                token?.let { put("Authorization", "Bearer $it") }
            }
            val (status, text) = try {
                transport.send(method, baseUrl + path + qs, headers, body?.let { encode(it).toString() }, timeout)
            } catch (e: IOException) {
                throw ApiError.Offline
            }
            if (status !in 200..299) throw mapError(status, text)
            if (text.isBlank()) JsonObject(emptyMap()) else (runCatching { json.parseToJsonElement(text) }.getOrNull() as? JsonObject ?: throw ApiError.Server(status))
        }

    private fun encode(map: Map<String, Any>): JsonObject = buildJsonObject {
        map.forEach { (k, v) ->
            put(k, when (v) { is Number -> JsonPrimitive(v); is Boolean -> JsonPrimitive(v); else -> JsonPrimitive(v.toString()) })
        }
    }
}

internal fun mapError(status: Int, text: String): ApiError {
    val body = runCatching { Json.parseToJsonElement(text) as? JsonObject }.getOrNull()
    val firstFieldError = (body?.obj("errors")?.values?.firstOrNull() as? JsonArray)?.firstOrNull()?.jsonPrimitive?.contentOrNull
    val message = firstFieldError ?: body?.str("message") ?: "حدث خطأ غير متوقع."
    return when {
        status == 401 -> ApiError.Unauthorized
        status == 403 && body?.bool("shop_expired") == true -> ApiError.ShopExpired(message)
        status == 403 && message.contains("تعطيل") -> ApiError.AccountDisabled(message)
        status in 400..499 -> ApiError.Rejected(status, message)
        else -> ApiError.Server(status)
    }
}
