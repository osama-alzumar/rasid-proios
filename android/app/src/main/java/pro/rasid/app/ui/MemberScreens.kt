package pro.rasid.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import pro.rasid.app.AppModel
import pro.rasid.core.ApiError
import pro.rasid.core.BalanceSummary
import pro.rasid.core.Formatting
import pro.rasid.core.Member
import pro.rasid.core.RewardRules
import pro.rasid.core.RewardType
import pro.rasid.core.RuleException
import pro.rasid.core.Shop
import pro.rasid.core.TransactionDraft
import pro.rasid.core.TxType

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScreenScaffoldTitle(title: String, onBack: () -> Unit) {
    TopAppBar(title = { Text(title) }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "رجوع") } })
}

@Composable
fun MemberDetailScreen(model: AppModel, memberId: Int, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val snapshot by model.snapshot.collectAsState()
    val member = snapshot.members[memberId]
    val shop = snapshot.shop
    var sheet by remember { mutableStateOf<TxType?>(null) }
    var addVehicle by remember { mutableStateOf(false) }
    var confirmation by remember { mutableStateOf<String?>(null) }
    if (addVehicle && member != null) { AddVehicleScreen(model, member.id) { addVehicle = false }; return }

    Column(Modifier.fillMaxSize()) {
        ScreenScaffoldTitle("العميل", onBack)
        if (member == null || shop == null) {
            Text("العميل غير موجود — ربما حُذف من لوحة التحكم.", Modifier.padding(24.dp))
        } else MemberDetailBody(model, member, shop, snapshot, confirmation, onEarn = { sheet = TxType.EARN }, onRedeem = { sheet = TxType.REDEEM }, onAddVehicle = { addVehicle = true })
    }
    if (member != null && shop != null) sheet?.let { type -> TransactionSheet(model, member, shop, type, onDismiss = { sheet = null }) { confirmation = it } }
}

@Composable
private fun MemberDetailBody(
    model: AppModel, member: Member, shop: Shop, snapshot: pro.rasid.core.Snapshot, confirmation: String?,
    onEarn: () -> Unit, onRedeem: () -> Unit, onAddVehicle: () -> Unit,
) {
        val balance = snapshot.displayBalance(member.id)
        val summary = BalanceSummary.of(shop, balance)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            SyncStatusBar(model)
            RasidCard {
                Text(member.name, Modifier.fillMaxWidth(), fontSize = 22.sp, fontWeight = FontWeight.Bold, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                    member.phone?.let { Icon(Icons.Filled.Phone, null, Modifier.padding(end = 4.dp)); Text(it, fontSize = 13.sp) }
                    Spacer(Modifier.width(12.dp))
                    member.externalId?.let { Icon(Icons.Filled.CreditCard, null, Modifier.padding(end = 4.dp)); Text(it, fontSize = 13.sp) }
                }
            }
            BalanceCard(summary, shop, snapshot.pendingDelta(member.id))
            confirmation?.let {
                Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.CheckCircle, null, tint = Brand.green); Spacer(Modifier.width(6.dp)); Text(it, color = Brand.green, fontWeight = FontWeight.SemiBold) }
            }
            if (snapshot.user?.canCreateTransactions == true) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    val earnTitle = when (shop.rewardType) { RewardType.POINTS -> "إضافة نقاط"; RewardType.STAMPS -> "إضافة ختم"; RewardType.VISITS -> "تسجيل زيارة" }
                    Button(onClick = onEarn, Modifier.weight(1f).height(84.dp).testTag("earn"), shape = RoundedCornerShape(18.dp)) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Filled.AddCircle, null); Text(earnTitle, fontWeight = FontWeight.Bold) }
                    }
                    Button(onClick = onRedeem, Modifier.weight(1f).height(84.dp), enabled = summary.rewardAvailable, shape = RoundedCornerShape(18.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Brand.orange)) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Filled.CardGiftcard, null); Text("استبدال", fontWeight = FontWeight.Bold) }
                    }
                }
            }
            if (shop.vehicleModuleEnabled) RasidCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("السيارات", Modifier.weight(1f), fontWeight = FontWeight.Bold)
                    if (snapshot.user?.canCreateVehicles == true) TextButton(onClick = onAddVehicle) { Text("+ إضافة") }
                }
                if (member.vehicles.isEmpty()) Text("لا توجد سيارات مسجلة", color = MaterialTheme.colorScheme.onSurfaceVariant)
                member.vehicles.forEach { v ->
                    Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        PlateChip(v.plateLettersAr, v.plateNumber); Spacer(Modifier.weight(1f)); Text(v.descriptionText, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            RasidCard {
                Text("آخر العمليات", fontWeight = FontWeight.Bold)
                val pending = snapshot.pending.filter { it.draft.memberId == member.id }
                val recent = snapshot.recentTransactions.filter { it.memberId == member.id }.take(10)
                if (pending.isEmpty() && recent.isEmpty()) Text("لا توجد عمليات حديثة على هذا الجهاز", color = MaterialTheme.colorScheme.onSurfaceVariant)
                pending.forEach { PendingRow(it) }
                recent.forEach { TransactionRow(it, showMember = false) }
            }
        }
}

/** Earn / redeem form; fields follow the shop's reward type like the website's cashier screen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TransactionSheet(model: AppModel, member: Member, shop: Shop, type: TxType, onDismiss: () -> Unit, onDone: (String) -> Unit) {
    val snapshot by model.snapshot.collectAsState()
    val services = snapshot.services.filter { it.isActive }
    var amount by remember { mutableStateOf("") }
    var count by remember { mutableStateOf("") }
    var invoice by remember { mutableStateOf("") }
    var serviceId by remember { mutableStateOf<Int?>(null) }
    var vehicleId by remember { mutableStateOf<Int?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val balance = snapshot.displayBalance(member.id)
    val draft = TransactionDraft(member.id, type, number(amount), number(count)?.toInt(), invoice.ifBlank { null }, vehicleId, serviceId)
    val service = serviceId?.let { id -> services.firstOrNull { it.id == id } }
    val preview = RewardRules.evaluate(draft, shop, balance, service)
    val spec = RewardRules.formSpec(shop, type, service != null)
    val unit = { n: Int -> when (shop.rewardType) { RewardType.POINTS -> "نقطة"; RewardType.STAMPS -> if (n == 1) "ختم" else "أختام"; RewardType.VISITS -> "زيارة" } }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 24.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(if (type == TxType.EARN) "عملية إضافة" else "استبدال مكافأة", fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Text("${member.name} · الرصيد الحالي $balance", color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (type == TxType.EARN && services.isNotEmpty()) Picker("الخدمة", listOf(null to "بدون خدمة") + services.map { it.id to (it.price?.let { p -> "${it.name} — ${Formatting.amount(p)} ر.س" } ?: it.name) }, serviceId) { serviceId = it }
            if (type == TxType.EARN && shop.vehicleModuleEnabled && member.vehicles.isNotEmpty()) Picker("السيارة", listOf(null to "بدون") + member.vehicles.map { it.id to it.plateText }, vehicleId) { vehicleId = it }
            if (spec.showsAmount) OutlinedTextField(amount, { amount = it }, Modifier.fillMaxWidth(), label = { Text(if (spec.amountRequired) "قيمة الفاتورة (ر.س)" else "قيمة الفاتورة (اختياري)") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true)
            if (spec.showsInvoice) OutlinedTextField(invoice, { invoice = it }, Modifier.fillMaxWidth().testTag("invoice"), label = { Text(if (spec.invoiceRequired) "رقم الفاتورة" else "رقم الفاتورة (اختياري)") }, singleLine = true)
            if (spec.showsCount) OutlinedTextField(count, { count = it }, Modifier.fillMaxWidth(), singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                label = { Text(when (shop.rewardType) { RewardType.POINTS -> "عدد النقاط المستبدلة"; RewardType.STAMPS -> "عدد الأختام (افتراضي ١)"; RewardType.VISITS -> "عدد الزيارات المضافة" }) })
            if (type == TxType.EARN && shop.rewardType == RewardType.STAMPS) shop.minStampAmount?.let { Text("يُحتسب الختم للفواتير من ${Formatting.amount(it)} ريال فأكثر.", fontSize = 12.sp) }
            preview.fold(
                { Text(if (type == TxType.EARN) "سيُضاف $it ${unit(it)}" else "سيُخصم $it ${unit(it)}", fontWeight = FontWeight.Bold, color = if (type == TxType.EARN) Brand.green else Brand.orange) },
                { if (type == TxType.REDEEM || amount.isNotEmpty() || count.isNotEmpty() || invoice.isNotEmpty() || serviceId != null) Text((it as RuleException).error.message, color = MaterialTheme.colorScheme.onSurfaceVariant) },
            )
            error?.let { Text(it, color = Color(0xFFE53935)) }
            Button(onClick = {
                saving = true; error = null
                scope.launch {
                    try {
                        val op = model.record(draft)
                        onDone(if (type == TxType.EARN) "تمت إضافة ${op.pointsChange} ${unit(op.pointsChange)}" else "تم خصم ${op.pointsChange} ${unit(op.pointsChange)}")
                        onDismiss()
                    } catch (e: RuleException) { error = e.error.message } catch (e: ApiError) { error = e.message }
                    saving = false
                }
            }, enabled = !saving && preview.isSuccess, modifier = Modifier.fillMaxWidth().height(50.dp).testTag("confirm")) { Text("تأكيد", fontWeight = FontWeight.Bold) }
        }
    }
}

/** Accepts Arabic-Indic digits and the Arabic decimal separator. */
private fun number(text: String): Double? {
    val map = mapOf('٠' to '0', '١' to '1', '٢' to '2', '٣' to '3', '٤' to '4', '٥' to '5', '٦' to '6', '٧' to '7', '٨' to '8', '٩' to '9', '٫' to '.', ',' to '.')
    return text.map { map[it] ?: it }.joinToString("").trim().takeIf { it.isNotEmpty() }?.toDoubleOrNull()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Picker(label: String, options: List<Pair<Int?, String>>, selected: Int?, onSelect: (Int?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded, { expanded = it }) {
        OutlinedTextField(options.firstOrNull { it.first == selected }?.second.orEmpty(), {}, readOnly = true, label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) }, modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable))
        androidx.compose.material3.DropdownMenu(expanded, { expanded = false }) {
            options.forEach { (id, text) -> DropdownMenuItem(text = { Text(text) }, onClick = { onSelect(id); expanded = false }) }
        }
    }
}

/** Registering a customer needs the server (card number + Wallet pass), so it is online-only. */
@Composable
fun AddMemberScreen(model: AppModel, onDone: (Member) -> Unit, onCancel: () -> Unit) {
    BackHandler(onBack = onCancel)
    var name by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    val online by model.isOnline.collectAsState()
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize()) {
        ScreenScaffoldTitle("عميل جديد", onCancel)
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), label = { Text("اسم العميل") }, singleLine = true)
            OutlinedTextField(phone, { phone = it }, Modifier.fillMaxWidth(), label = { Text("رقم الجوال") }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone))
            Text("تُنشأ بطاقة العميل في المحفظة تلقائياً بعد التسجيل.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (!online) Text("تسجيل عميل جديد يحتاج اتصالاً بالإنترنت.", color = Brand.orange)
            error?.let { Text(it, color = Color(0xFFE53935)) }
            Button(onClick = {
                saving = true; error = null
                scope.launch {
                    try { onDone(model.createMember(name.trim(), phone.trim())) }
                    catch (e: ApiError) { error = if (e is ApiError.Offline) "لا يوجد اتصال. سجّل العميل عند عودة الإنترنت." else e.message }
                    saving = false
                }
            }, enabled = !saving && name.isNotBlank(), modifier = Modifier.fillMaxWidth().height(50.dp)) { Text("تسجيل", fontWeight = FontWeight.Bold) }
        }
    }
}

@Composable
private fun AddVehicleScreen(model: AppModel, memberId: Int, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    var letters by remember { mutableStateOf("") }
    var number by remember { mutableStateOf("") }
    var make by remember { mutableStateOf("") }
    var carModel by remember { mutableStateOf("") }
    var color by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ScreenScaffoldTitle("إضافة سيارة", onClose)
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(letters, { letters = it }, Modifier.fillMaxWidth(), label = { Text("الحروف بالعربي (مثال: أ ب ج)") }, singleLine = true)
            OutlinedTextField(number, { number = it }, Modifier.fillMaxWidth(), label = { Text("الأرقام") }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
            OutlinedTextField(make, { make = it }, Modifier.fillMaxWidth(), label = { Text("الشركة (اختياري)") }, singleLine = true)
            OutlinedTextField(carModel, { carModel = it }, Modifier.fillMaxWidth(), label = { Text("الموديل (اختياري)") }, singleLine = true)
            OutlinedTextField(color, { color = it }, Modifier.fillMaxWidth(), label = { Text("اللون (اختياري)") }, singleLine = true)
            error?.let { Text(it, color = Color(0xFFE53935)) }
            Button(onClick = {
                saving = true; error = null
                scope.launch {
                    try { model.createVehicle(memberId, letters, number, make, carModel, color); onClose() }
                    catch (e: ApiError) { error = if (e is ApiError.Offline) "إضافة سيارة تحتاج اتصالاً بالإنترنت." else e.message }
                    saving = false
                }
            }, enabled = !saving && letters.isNotBlank() && number.isNotBlank(), modifier = Modifier.fillMaxWidth().height(50.dp)) { Text("حفظ", fontWeight = FontWeight.Bold) }
        }
    }
}
