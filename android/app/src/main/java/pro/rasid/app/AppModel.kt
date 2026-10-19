package pro.rasid.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import pro.rasid.core.ApiClient
import pro.rasid.core.ApiError
import pro.rasid.core.Bootstrap
import pro.rasid.core.DashboardStats
import pro.rasid.core.LocalStore
import pro.rasid.core.Member
import pro.rasid.core.MembersPage
import pro.rasid.core.PendingOperation
import pro.rasid.core.PlatformStats
import pro.rasid.core.RewardType
import pro.rasid.core.SelfScanSettings
import pro.rasid.core.Role
import pro.rasid.core.ServerTransaction
import pro.rasid.core.Service
import pro.rasid.core.Shop
import pro.rasid.core.Snapshot
import pro.rasid.core.SyncEngine
import pro.rasid.core.SystemMessage
import pro.rasid.core.TransactionDraft
import pro.rasid.core.TxType
import pro.rasid.core.User
import pro.rasid.core.Vehicle
import pro.rasid.core.WalletReach
import java.io.File

enum class Appearance(val title: String) { SYSTEM("تلقائي (حسب الجهاز)"), LIGHT("فاتح"), DARK("ليلي") }

/** App-wide state: session, the offline snapshot, background sync, announcements. */
class AppModel private constructor(private val context: Context, val isDemo: Boolean, private val demoRole: Role) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val prefs = context.getSharedPreferences("rasid", Context.MODE_PRIVATE)
    private val tokens = TokenStore(context)
    private val store = LocalStore(if (isDemo) null else File(context.filesDir, "rasid/store.json"))
    private var api = ApiClient(if (isDemo) null else tokens.load())
    private val syncLock = Mutex()
    private var syncJob: Job? = null
    private var fetchedSystemMessages = false

    val loggedIn = MutableStateFlow(isDemo || tokens.load() != null)
    private val _snapshot = MutableStateFlow(store.snapshot)
    val snapshot: StateFlow<Snapshot> = _snapshot.asStateFlow()
    val isOnline = MutableStateFlow(true)
    val isSyncing = MutableStateFlow(false)
    val lastSyncError = MutableStateFlow<String?>(null)
    /** Full-screen: shop subscription ended / account disabled. */
    val blockingMessage = MutableStateFlow<String?>(null)
    /** The platform owner's session is locked behind biometrics on every return. */
    val isLocked = MutableStateFlow(loggedIn.value && !isDemo && prefs.getBoolean(KEY_OWNER, false))
    val systemMessages = MutableStateFlow<List<SystemMessage>>(emptyList())
    val appearance = MutableStateFlow(runCatching { Appearance.valueOf(prefs.getString(KEY_APPEARANCE, null) ?: "SYSTEM") }.getOrDefault(Appearance.SYSTEM))

    companion object {
        private const val KEY_OWNER = "ownerSession"
        private const val KEY_APPEARANCE = "appearance"
        fun create(context: Context, demo: Boolean, demoRole: Role) = AppModel(context.applicationContext, demo, demoRole)
    }

    init {
        if (isDemo) scope.launch { loadDemo() } else {
            monitorNetwork()
            scope.launch {
                while (true) { delay(15_000); syncSoon() }
            }
            if (loggedIn.value) { syncSoon(); fetchSystemMessagesIfNeeded() }
        }
    }

    // ---- derived ----
    val user: User? get() = _snapshot.value.user
    val shop: Shop? get() = _snapshot.value.shop
    fun balance(member: Member) = _snapshot.value.displayBalance(member.id)
    val needsShopSelection get() = user?.isSuperAdmin == true && _snapshot.value.selectedShopId == null
    val canMessageCustomers get() = shop != null && (user?.isManager == true || (user?.isSuperAdmin == true && _snapshot.value.selectedShopId != null))
    private val workingShopId get() = if (user?.isSuperAdmin == true) _snapshot.value.selectedShopId else null
    private fun reload() { _snapshot.value = store.snapshot }

    fun setAppearance(a: Appearance) { appearance.value = a; prefs.edit().putString(KEY_APPEARANCE, a.name).apply() }

    // ---- session ----
    suspend fun login(email: String, password: String) {
        val result = ApiClient().login(email.trim(), password)
        if (result.user.role !in setOf(Role.CASHIER, Role.SHOP_MANAGER, Role.SUPER_ADMIN)) {
            throw ApiError.Rejected(403, "هذا التطبيق مخصص لحسابات التاجر والكاشير ومدير النظام.")
        }
        tokens.save(result.token)
        prefs.edit().putBoolean(KEY_OWNER, result.user.isSuperAdmin).apply()
        api = ApiClient(result.token)
        store.replaceSession(result.user)
        reload()
        loggedIn.value = true
        syncNow()
        fetchSystemMessages()
    }

    fun logout() = scope.launch {
        if (!isDemo) runCatching { api.logout() }
        tokens.clear()
        prefs.edit().remove(KEY_OWNER).apply()
        api = ApiClient()
        store.clear(); reload()
        blockingMessage.value = null; lastSyncError.value = null; systemMessages.value = emptyList()
        fetchedSystemMessages = false; isLocked.value = false
        loggedIn.value = false
    }

    // ---- sync ----
    fun syncSoon() {
        if (!loggedIn.value || isDemo || isLocked.value) return
        if (syncJob?.isActive == true) return
        syncJob = scope.launch { syncNow() }
    }

    suspend fun syncNow() {
        if (!loggedIn.value || isDemo) return
        syncLock.withLock {
            isSyncing.value = true
            try {
                val report = SyncEngine(store, api).sync()
                lastSyncError.value = if (report.offline) ApiError.Offline.message else null
                if (!report.offline) blockingMessage.value = null
            } catch (e: ApiError) {
                when (e) {
                    is ApiError.Unauthorized -> logout()
                    is ApiError.ShopExpired -> blockingMessage.value = e.text
                    is ApiError.AccountDisabled -> blockingMessage.value = e.text
                    else -> lastSyncError.value = e.message
                }
            } finally {
                isSyncing.value = false
                reload()
            }
        }
    }

    private fun monitorNetwork() {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return
        isOnline.value = cm.activeNetwork != null
        val request = NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build()
        cm.registerNetworkCallback(request, object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { scope.launch { val cameBack = !isOnline.value; isOnline.value = true; if (cameBack) syncSoon() } }
            override fun onLost(network: Network) { scope.launch { isOnline.value = cm.activeNetwork != null } }
        })
    }

    // ---- owner lock ----
    fun lockIfNeeded() { if (loggedIn.value && !isDemo && prefs.getBoolean(KEY_OWNER, false)) isLocked.value = true }
    fun unlocked() { isLocked.value = false; syncSoon() }

    // ---- system messages (fetched at login and once per launch, like the website) ----
    fun fetchSystemMessagesIfNeeded() { if (!fetchedSystemMessages && loggedIn.value) scope.launch { fetchSystemMessages() } }

    private suspend fun fetchSystemMessages() {
        if (isDemo) return
        runCatching { api.pendingSystemMessages() }.onSuccess { systemMessages.value = it; fetchedSystemMessages = true }
    }

    fun acknowledge(message: SystemMessage) {
        systemMessages.value = systemMessages.value.filter { it.id != message.id }
        if (!isDemo) scope.launch { runCatching { api.acknowledgeSystemMessage(message.id) } }
    }

    fun dismiss(message: SystemMessage) { systemMessages.value = systemMessages.value.filter { it.id != message.id } }

    // ---- cashier actions ----
    suspend fun findMember(code: String): Member {
        store.findMember(code)?.let { return it }
        if (isDemo) throw ApiError.Rejected(404, "لم يتم العثور على العميل.")
        val member = try { api.lookupMember(code) } catch (e: ApiError.Rejected) {
            throw if (e.status == 404) ApiError.Rejected(404, "لم يتم العثور على عميل بهذا الرمز.") else e
        }
        workingShopId?.let { if (member.shopId != it) throw ApiError.Rejected(404, "هذا العميل مسجل في محل آخر.") }
        store.upsertMember(member); reload()
        return member
    }

    fun searchMembers(query: String) = store.searchMembers(query)

    /** Quick scan: scanning a card adds one stamp straight away (per device). */
    var quickScanEnabled: Boolean
        get() = prefs.getBoolean("quickScanEnabled", true)
        set(value) = prefs.edit().putBoolean("quickScanEnabled", value).apply()

    /** Records the operation on the device immediately, then tries to send it. */
    suspend fun record(draft: TransactionDraft): PendingOperation {
        val op = store.enqueue(draft); reload(); syncSoon(); return op
    }

    fun discard(op: PendingOperation) = scope.launch { store.discard(op.id); reload() }

    suspend fun createMember(name: String, phone: String?): Member {
        val m = api.createMember(name, phone, workingShopId); store.upsertMember(m); reload(); return m
    }

    suspend fun createVehicle(memberId: Int, letters: String, number: String, make: String?, model: String?, color: String?) {
        store.addVehicle(api.createVehicle(memberId, letters, number, make, model, color)); reload()
    }

    suspend fun dashboard(period: String): DashboardStats = api.dashboardStats(period)
    suspend fun platformStats(period: String): PlatformStats = api.platformStats(period)
    suspend fun shops(search: String): List<Shop> = api.shops(search)

    suspend fun selectShop(shop: Shop) { store.selectShop(shop); reload(); syncNow() }

    suspend fun sendStoreMessage(message: String): WalletReach? {
        val s = shop ?: throw ApiError.Rejected(400, "لا يوجد محل محدد.")
        val reach = api.sendStoreMessage(s.id, message); syncNow(); return reach
    }

    /** Same people who message customers: the shop's manager and the owner. */
    val canManageSelfScan get() = canMessageCustomers

    private var demoSelfScan = SelfScanSettings(enabled = false, available = true)

    suspend fun selfScan(): SelfScanSettings {
        val s = shop ?: throw ApiError.Rejected(400, "لا يوجد محل محدد.")
        return if (isDemo) demoSelfScan else api.selfScan(s.id)
    }

    suspend fun setSelfScan(enabled: Boolean, newCode: Boolean = false): SelfScanSettings {
        val s = shop ?: throw ApiError.Rejected(400, "لا يوجد محل محدد.")
        if (isDemo) {
            demoSelfScan = demoSelfScan.copy(enabled = enabled, url = if (enabled) "https://rasid.pro/backend/s/demo" else null,
                posterUrl = if (enabled) "https://rasid.pro/backend/s/demo/poster" else null)
            return demoSelfScan
        }
        return api.updateSelfScan(s.id, enabled, newCode)
    }

    // ---- demo (CI screenshots only; debug builds) ----
    private suspend fun loadDemo() {
        val user = User(1, "أحمد الكاشير", "cashier@demo.rasid.pro", 1, demoRole,
            listOf("members.view-any", "members.create", "transactions.create", "vehicles.create"))
        store.replaceSession(user)
        val shop = Shop(1, "مغسلة اللمعة", RewardType.STAMPS, numberOfStamps = 6, storeMessage = "الغسلة السابعة مجاناً", vehicleModuleEnabled = true)
        store.applyBootstrap(Bootstrap("", user, shop, listOf(Service(1, "غسيل خارجي", 25.0), Service(2, "غسيل شامل", 45.0)), WalletReach(1240, 1386)))
        store.applyMembersPage(MembersPage(listOf(
            Member(1, 1, "سارة العتيبي", "0551112222", "EXT_104233", currentBalance = 4, vehicles = listOf(Vehicle(1, 1, "أ ب ج", "1234", make = "تويوتا", model = "كامري", color = "أبيض"))),
            Member(2, 1, "خالد الشهري", "0553334444", "EXT_582910", currentBalance = 6),
            Member(3, 1, "منى القحطاني", "0555556666", "EXT_771205", currentBalance = 1),
            Member(4, 1, "فهد الدوسري", "0557778888", "EXT_330418", currentBalance = 3),
        ), "", false, null, null))
        store.setRecentTransactions(listOf(
            ServerTransaction(3, 2, "خالد الشهري", "غسيل شامل", pointsChange = 1, type = TxType.EARN, createdBy = "أحمد", createdAt = "2026-10-13 11:42:00"),
            ServerTransaction(2, 1, "سارة العتيبي", "غسيل خارجي", pointsChange = 1, type = TxType.EARN, createdBy = "أحمد", createdAt = "2026-10-13 10:15:00"),
            ServerTransaction(1, 3, "منى القحطاني", pointsChange = 6, type = TxType.REDEEM, createdBy = "أحمد", createdAt = "2026-10-12 18:03:00"),
        ))
        store.finishMembersSync("")
        reload()
    }

    fun showDemoSystemMessage() {
        systemMessages.value = listOf(SystemMessage(1, "تحديث مهم", "أضفنا ميزة رسالة للعملاء: أرسل عروضك لعملائك فتصلهم إشعاراً على بطاقة المحفظة.", SystemMessage.Tone.SUCCESS, true))
    }
}
