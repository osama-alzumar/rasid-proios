package pro.rasid.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import pro.rasid.app.AppModel
import pro.rasid.app.Appearance
import pro.rasid.app.BuildConfig
import pro.rasid.app.R
import pro.rasid.core.ApiError
import pro.rasid.core.BalanceSummary
import pro.rasid.core.DashboardStats
import pro.rasid.core.Member
import pro.rasid.core.PlatformStats
import pro.rasid.core.RewardType
import pro.rasid.core.Shop
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
private fun Title(text: String) = Text(text, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 4.dp))

// ---------------- Customers ----------------

@Composable
fun MembersScreen(model: AppModel) {
    val snapshot by model.snapshot.collectAsState()
    var query by remember { mutableStateOf("") }
    var opened by remember { mutableStateOf<Int?>(null) }
    var adding by remember { mutableStateOf(false) }
    opened?.let { MemberDetailScreen(model, it) { opened = null }; return }
    if (adding) { AddMemberScreen(model, onDone = { adding = false; opened = it.id }, onCancel = { adding = false }); return }
    val results = remember(query, snapshot.members, snapshot.lastSuccessfulSyncMillis) { model.searchMembers(query) }

    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        Row(Modifier.padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { Title("العملاء") }
            if (snapshot.user?.canCreateMembers == true) TextButton(onClick = { adding = true }) { Icon(Icons.Filled.PersonAdd, "تسجيل عميل جديد") }
        }
        SyncStatusBar(model)
        OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().padding(vertical = 8.dp), placeholder = { Text("الاسم أو الجوال أو اللوحة") }, singleLine = true, shape = RoundedCornerShape(14.dp))
        Text("${snapshot.members.size} عميل محفوظ على الجهاز", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (results.isEmpty()) Text(if (query.isEmpty()) "سيظهر العملاء هنا بعد أول مزامنة." else "لا توجد نتائج", Modifier.padding(32.dp).fillMaxWidth(), color = MaterialTheme.colorScheme.onSurfaceVariant)
        LazyColumn(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            items(results, key = { it.id }) { m -> MemberRow(model, m, snapshot.shop) { opened = m.id } }
        }
    }
}

@Composable
private fun MemberRow(model: AppModel, m: Member, shop: Shop?, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Avatar(m.name); Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(m.name, fontWeight = FontWeight.SemiBold)
            Text(m.phone ?: m.externalId.orEmpty(), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        shop?.let {
            val s = BalanceSummary.of(it, model.balance(m))
            Column(horizontalAlignment = Alignment.End) { Ltr { Text(s.headline, fontWeight = FontWeight.Bold) }; Text(s.unit, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}

// ---------------- History ----------------

@Composable
fun HistoryScreen(model: AppModel) {
    val snapshot by model.snapshot.collectAsState()
    var discard by remember { mutableStateOf<pro.rasid.core.PendingOperation?>(null) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Title("السجل")
        val rejected = snapshot.pending.filter { it.rejected }
        val pending = snapshot.pending.filter { !it.rejected }
        if (rejected.isNotEmpty()) RasidCard {
            Text("رفضها الخادم", fontWeight = FontWeight.Bold, color = Color(0xFFE53935))
            rejected.forEach { op -> Box(Modifier.clickable { discard = op }) { PendingRow(op) } }
            Text("هذه العمليات لم تُحتسب. اضغط على العملية لحذفها بعد مراجعتها.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (pending.isNotEmpty()) RasidCard {
            Text("بانتظار الإرسال", fontWeight = FontWeight.Bold)
            pending.forEach { PendingRow(it) }
            Text("تُرسل تلقائياً عند توفر الاتصال.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        RasidCard {
            Text("آخر العمليات", fontWeight = FontWeight.Bold)
            if (snapshot.recentTransactions.isEmpty()) Text("لا توجد عمليات بعد", color = MaterialTheme.colorScheme.onSurfaceVariant)
            snapshot.recentTransactions.forEach { TransactionRow(it, showMember = true) }
        }
    }
    discard?.let { op ->
        AlertDialog(onDismissRequest = { discard = null }, title = { Text("حذف العملية المرفوضة؟") },
            confirmButton = { TextButton(onClick = { model.discard(op); discard = null }) { Text("حذف", color = Color(0xFFE53935)) } },
            dismissButton = { TextButton(onClick = { discard = null }) { Text("إلغاء") } })
    }
}

// ---------------- Merchant dashboard ----------------

@Composable
private fun PeriodPicker(period: String, onChange: (String) -> Unit) {
    val options = listOf("today" to "اليوم", "week" to "٧ أيام", "month" to "٣٠ يوماً")
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        options.forEachIndexed { i, (key, label) ->
            SegmentedButton(selected = period == key, onClick = { onChange(key) }, shape = SegmentedButtonDefaults.itemShape(i, options.size)) { Text(label) }
        }
    }
}

@Composable
fun DashboardScreen(model: AppModel) {
    var period by remember { mutableStateOf("today") }
    var stats by remember { mutableStateOf<DashboardStats?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var composing by remember { mutableStateOf(false) }
    val snapshot by model.snapshot.collectAsState()
    if (composing) { StoreMessageScreen(model) { composing = false }; return }
    LaunchedEffect(period) {
        if (!model.isDemo) runCatching { model.dashboard(period) }.onSuccess { stats = it; error = null }.onFailure { error = it.message }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Title(snapshot.shop?.name ?: "الرئيسية")
        SyncStatusBar(model)
        if (model.canMessageCustomers) RasidCard(Modifier.clickable { composing = true }.testTag("compose")) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(44.dp).background(Brand.green, RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) { Icon(Icons.AutoMirrored.Filled.Send, null, tint = Color.White) }
                Spacer(Modifier.width(12.dp))
                Column {
                    Text("رسالة للعملاء", fontWeight = FontWeight.Bold)
                    Text(snapshot.walletReach?.let { "تصل إشعاراً إلى ${it.devices} جهاز" } ?: "تصل إشعاراً على بطاقتهم في المحفظة", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        PeriodPicker(period) { period = it }
        if (stats == null && error != null) Text("تعذر تحميل الإحصائيات: $error", color = MaterialTheme.colorScheme.onSurfaceVariant)
        stats?.let { s ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatTile("العملاء", s.customers.value, s.customers.trend, Icons.Filled.People, Modifier.weight(1f))
                StatTile("عملاء جدد", s.newCustomers.value, s.newCustomers.trend, Icons.Filled.PersonAdd, Modifier.weight(1f))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatTile("العمليات", s.transactions.value, s.transactions.trend, Icons.Filled.SwapHoriz, Modifier.weight(1f))
                StatTile("الاستبدالات", s.redemptions.value, s.redemptions.trend, Icons.Filled.CardGiftcard, Modifier.weight(1f))
            }
            RasidCard {
                Text("النشاط", fontWeight = FontWeight.Bold)
                ActivityChart(s.chart)
            }
            RasidCard {
                Text("آخر النشاطات", fontWeight = FontWeight.Bold)
                if (s.recent.isEmpty()) Text("لا يوجد نشاط بعد", color = MaterialTheme.colorScheme.onSurfaceVariant)
                s.recent.forEach { a ->
                    Text("${a.memberName ?: "—"} · " + when (a.type) { "new_member" -> "عميل جديد"; "reward_redeemed" -> "استبدال ${a.amount ?: 0}"; else -> "إضافة ${a.amount ?: 0}" }, Modifier.padding(vertical = 4.dp))
                }
            }
        }
    }
}

/** Earn (green) vs redeem (orange) bars per bucket. */
@Composable
private fun ActivityChart(points: List<Pair<Int, Int>>) {
    val green = Brand.green
    val orange = Brand.orange
    Canvas(Modifier.fillMaxWidth().height(160.dp).padding(top = 8.dp)) {
        if (points.isEmpty()) return@Canvas
        val max = points.maxOf { it.first + it.second }.coerceAtLeast(1)
        val slot = size.width / points.size
        val bar = (slot * 0.6f).coerceAtMost(28f)
        points.forEachIndexed { i, (earn, redeem) ->
            val x = size.width - (i + 1) * slot + (slot - bar) / 2 // RTL: newest on the left edge
            val earnH = size.height * earn / max
            val redeemH = size.height * redeem / max
            drawRoundRect(green, Offset(x, size.height - earnH), Size(bar, earnH), CornerRadius(6f))
            drawRoundRect(orange, Offset(x, size.height - earnH - redeemH), Size(bar, redeemH), CornerRadius(6f))
        }
    }
}

// ---------------- Platform owner ----------------

@Composable
fun PlatformScreen(model: AppModel) {
    var period by remember { mutableStateOf("today") }
    var stats by remember { mutableStateOf<PlatformStats?>(null) }
    var shops by remember { mutableStateOf<List<Shop>>(emptyList()) }
    var search by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var switching by remember { mutableStateOf<Int?>(null) }
    val snapshot by model.snapshot.collectAsState()
    val scope = rememberCoroutineScope()
    LaunchedEffect(period) { runCatching { model.platformStats(period) }.onSuccess { stats = it }.onFailure { error = it.message } }
    LaunchedEffect(search) { delay(350); runCatching { model.shops(search) }.onSuccess { shops = it; error = null }.onFailure { error = it.message } }

    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { Spacer(Modifier.height(12.dp)); Title("المنصة"); SyncStatusBar(model) }
        item { PeriodPicker(period) { period = it } }
        stats?.let { s ->
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    StatTile("المحلات", s.shops.value, s.shops.trend, Icons.Filled.Apartment, Modifier.weight(1f))
                    StatTile("اشتراكات فعالة", s.activeSubscriptions.value, s.activeSubscriptions.trend, Icons.Filled.Verified, Modifier.weight(1f))
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    StatTile("العملاء", s.customers.value, s.customers.trend, Icons.Filled.People, Modifier.weight(1f))
                    StatTile("العمليات", s.transactions.value, s.transactions.trend, Icons.Filled.SwapHoriz, Modifier.weight(1f))
                }
            }
            if (s.topShops.isNotEmpty()) item {
                RasidCard {
                    Text("الأكثر نشاطاً", fontWeight = FontWeight.Bold)
                    s.topShops.forEach { (name, count) -> Row(Modifier.padding(vertical = 4.dp)) { Text(name, Modifier.weight(1f)); Text("$count عملية", fontSize = 12.sp) } }
                }
            }
        }
        item {
            Text("المحلات", fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))
            OutlinedTextField(search, { search = it }, Modifier.fillMaxWidth(), placeholder = { Text("ابحث باسم المحل") }, singleLine = true, shape = RoundedCornerShape(14.dp))
            error?.let { Text(it, color = Brand.orange) }
            Text("اختر محلاً لتعمل عليه من تبويبات المسح والعملاء والسجل، كأنك كاشير فيه.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        items(shops, key = { it.id }) { shop ->
            Row(Modifier.fillMaxWidth().clickable(enabled = switching == null) {
                switching = shop.id
                scope.launch {
                    try { model.selectShop(shop) } catch (e: ApiError) { error = e.message }
                    switching = null
                }
            }.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(shop.name, fontWeight = FontWeight.SemiBold)
                    val type = when (shop.rewardType) { RewardType.POINTS -> "نقاط"; RewardType.STAMPS -> "أختام"; RewardType.VISITS -> "زيارات" }
                    Text(if (shop.isExpired) "منتهي الاشتراك · $type" else type + (shop.membersCount?.let { " · $it عميل" } ?: ""), fontSize = 12.sp,
                        color = if (shop.isExpired) Color(0xFFE53935) else MaterialTheme.colorScheme.onSurfaceVariant)
                }
                when {
                    switching == shop.id -> CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    snapshot.selectedShopId == shop.id -> Icon(Icons.Filled.CheckCircle, "المحل الحالي", tint = Brand.green)
                }
            }
            HorizontalDivider()
        }
    }
}

// ---------------- Settings ----------------

@Composable
fun SettingsScreen(model: AppModel) {
    val snapshot by model.snapshot.collectAsState()
    val appearance by model.appearance.collectAsState()
    val online by model.isOnline.collectAsState()
    val syncing by model.isSyncing.collectAsState()
    val syncError by model.lastSyncError.collectAsState()
    var confirmLogout by remember { mutableStateOf(false) }
    var composing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val uri = LocalUriHandler.current
    if (composing) { StoreMessageScreen(model) { composing = false }; return }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Title("الإعدادات")
        snapshot.user?.let { u ->
            RasidCard {
                Text("الحساب", fontWeight = FontWeight.Bold)
                Info("الاسم", u.name); Info("البريد", u.email)
                Info("الصلاحية", if (u.isSuperAdmin) "مدير النظام" else if (u.isManager) "مدير المحل" else "كاشير")
                snapshot.shop?.let { Info("المحل", it.name); it.expiresAt?.let { e -> Info("ينتهي الاشتراك", e) } }
            }
        }
        if (model.canMessageCustomers) RasidCard(Modifier.clickable { composing = true }) {
            Text("التواصل مع العملاء", fontWeight = FontWeight.Bold)
            Row(Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.AutoMirrored.Filled.Send, null, tint = Brand.green); Spacer(Modifier.width(8.dp)); Text("رسالة للعملاء") }
            Text("ترسل إشعاراً لكل عميل أضاف بطاقة المحل إلى Apple Wallet.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        RasidCard {
            Text("المظهر", fontWeight = FontWeight.Bold)
            Appearance.entries.forEach { a ->
                Row(Modifier.fillMaxWidth().clickable { model.setAppearance(a) }, verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = appearance == a, onClick = { model.setAppearance(a) }); Text(a.title)
                }
            }
        }
        RasidCard {
            Text("المزامنة", fontWeight = FontWeight.Bold)
            Info("الاتصال", if (online) "متصل" else "غير متصل")
            Info("العملاء على الجهاز", "${snapshot.members.size}")
            Info("بانتظار الإرسال", "${snapshot.pendingCount}")
            snapshot.lastSuccessfulSyncMillis?.let { Info("آخر مزامنة", SimpleDateFormat("d MMM HH:mm", Locale("ar")).format(Date(it))) }
            syncError?.let { Text(it, color = Brand.orange, fontSize = 12.sp) }
            Button(onClick = { scope.launch { model.syncNow() } }, enabled = !syncing, modifier = Modifier.fillMaxWidth()) { Text(if (syncing) "جارٍ المزامنة…" else "مزامنة الآن") }
            Text("يحتفظ التطبيق بنسخة من بيانات المحل ليعمل بدون إنترنت، ويرسل العمليات تلقائياً عند عودة الاتصال.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        RasidCard {
            TextButton(onClick = { uri.openUri("https://info.rasid.pro/privacy-policy/") }) { Text("سياسة الخصوصية") }
            TextButton(onClick = { uri.openUri("https://info.rasid.pro/") }) { Text("موقع رصيد") }
        }
        TextButton(onClick = { confirmLogout = true }, modifier = Modifier.fillMaxWidth()) { Text("تسجيل الخروج", color = Color(0xFFE53935)) }
        Text("الإصدار ${BuildConfig.VERSION_NAME}", Modifier.fillMaxWidth(), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if (confirmLogout) AlertDialog(onDismissRequest = { confirmLogout = false },
        title = { Text("تسجيل الخروج") },
        text = { Text(if (snapshot.pendingCount > 0) "يوجد ${snapshot.pendingCount} عملية لم تُرسل بعد وستُحذف من الجهاز عند الخروج. انتظر حتى تتم المزامنة إن أمكن." else "هل تريد تسجيل الخروج من هذا الجهاز؟") },
        confirmButton = { TextButton(onClick = { confirmLogout = false; model.logout() }) { Text("تسجيل الخروج", color = Color(0xFFE53935)) } },
        dismissButton = { TextButton(onClick = { confirmLogout = false }) { Text("إلغاء") } })
}

@Composable
private fun Info(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Text(label, Modifier.weight(1f)); Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

// ---------------- Store message ----------------

/** Message to every customer holding the shop's Wallet card; Wallet shows it on the lock screen. */
@Composable
fun StoreMessageScreen(model: AppModel, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    val snapshot by model.snapshot.collectAsState()
    val online by model.isOnline.collectAsState()
    var text by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf(false) }
    var sending by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val trimmed = text.trim()
    val reach = snapshot.walletReach

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ScreenScaffoldTitle("رسالة للعملاء", onClose)
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(text, { if (it.length <= 1000) text = it }, Modifier.fillMaxWidth().heightIn(min = 130.dp).testTag("message"),
                label = { Text("الرسالة") }, placeholder = { Text("مثال: عرض نهاية الأسبوع — القهوة الثانية مجاناً حتى الأحد ☕") })
            Row {
                Ltr { Text("${trimmed.length} / 1000", fontSize = 12.sp, color = if (trimmed.length > 150) Brand.orange else MaterialTheme.colorScheme.onSurfaceVariant) }
                Spacer(Modifier.weight(1f))
                if (trimmed.length > 150) Text("الإشعار يعرض أول 150 حرف تقريباً", fontSize = 12.sp, color = Brand.orange)
            }
            Text("تظهر كإشعار على شاشة القفل عند العملاء، وتبقى مكتوبة خلف بطاقتهم في المحفظة حتى ترسل رسالة جديدة.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (trimmed.isNotEmpty()) {
                Text("كيف تظهر عند العميل", fontWeight = FontWeight.Bold)
                Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(20.dp)).padding(12.dp)) {
                    Box(Modifier.size(38.dp).background(Brand.navy, RoundedCornerShape(9.dp)).padding(5.dp)) { Image(painterResource(R.drawable.logo), null) }
                    Spacer(Modifier.width(10.dp))
                    Column {
                        Row { Text(snapshot.shop?.name ?: "رصيد", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f)); Text("الآن", fontSize = 12.sp) }
                        Text(trimmed, maxLines = 4, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            RasidCard {
                Text("المستلمون", fontWeight = FontWeight.Bold)
                reach?.let { Info("عملاء أضافوا البطاقة", "${it.cards}"); Info("أجهزة تستقبل الإشعار", "${it.devices}") }
                snapshot.shop?.storeMessage?.takeIf { it.isNotBlank() }?.let { Info("الرسالة الحالية", it) }
                Text("يصل الإشعار لمن أضاف البطاقة إلى Apple Wallet وفعّل التحديثات التلقائية لها.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            result?.let { Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.CheckCircle, null, tint = Brand.green); Spacer(Modifier.width(6.dp)); Text(it, color = Brand.green) } }
            error?.let { Text(it, color = Color(0xFFE53935)) }
            if (!online) Text("الإرسال يحتاج اتصالاً بالإنترنت.", color = Brand.orange)
            Button(onClick = { confirm = true }, enabled = trimmed.isNotEmpty() && !sending && online, modifier = Modifier.fillMaxWidth().height(50.dp)) {
                if (sending) CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp) else Text("إرسال للعملاء", fontWeight = FontWeight.Bold)
            }
        }
    }
    if (confirm) AlertDialog(onDismissRequest = { confirm = false },
        title = { Text(reach?.devices?.takeIf { it > 0 }?.let { "إرسال الرسالة إلى $it جهاز؟" } ?: "إرسال الرسالة لكل العملاء؟") },
        text = { Text("ستحل محل الرسالة الحالية على بطاقات العملاء.") },
        confirmButton = {
            TextButton(onClick = {
                confirm = false; sending = true; error = null; result = null
                scope.launch {
                    try {
                        val sent = model.sendStoreMessage(trimmed)
                        result = sent?.let { "تم الإرسال. تصل الرسالة إلى ${it.devices} جهاز خلال دقائق." } ?: "تم الإرسال."
                        text = ""
                    } catch (e: ApiError) { error = if (e is ApiError.Offline) "تعذر الاتصال. لم تُرسل الرسالة، حاول مرة أخرى." else e.message }
                    sending = false
                }
            }) { Text("إرسال") }
        },
        dismissButton = { TextButton(onClick = { confirm = false }) { Text("إلغاء") } })
}
