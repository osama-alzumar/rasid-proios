package pro.rasid.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import pro.rasid.app.AppModel
import pro.rasid.core.SystemMessage

enum class Tab(val title: String, val icon: ImageVector) {
    PLATFORM("المنصة", Icons.Filled.Apartment), HOME("الرئيسية", Icons.Filled.BarChart), SCAN("المسح", Icons.Filled.QrCodeScanner),
    MEMBERS("العملاء", Icons.Filled.People), HISTORY("السجل", Icons.Filled.History), SETTINGS("الإعدادات", Icons.Filled.Settings)
}

@Composable
fun RasidRoot(model: AppModel, authenticate: ((String?) -> Unit) -> Unit) {
    val appearance by model.appearance.collectAsState()
    val loggedIn by model.loggedIn.collectAsState()
    val blocking by model.blockingMessage.collectAsState()
    val locked by model.isLocked.collectAsState()
    val messages by model.systemMessages.collectAsState()

    RasidTheme(appearance) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            when {
                !loggedIn -> LoginScreen(model)
                blocking != null -> BlockedScreen(model, blocking!!)
                else -> MainTabs(model)
            }
            if (locked) LockScreen(model, authenticate)
            val current = messages.firstOrNull()
            if (!locked && current != null) SystemMessageDialog(model, current)
        }
    }
}

@Composable
private fun MainTabs(model: AppModel) {
    val snapshot by model.snapshot.collectAsState()
    val user = snapshot.user
    val tabs = buildList {
        if (user?.isSuperAdmin == true) add(Tab.PLATFORM)
        if (model.needsShopSelection) add(Tab.SETTINGS) else {
            if (user?.isManager == true) add(Tab.HOME)
            if (user?.isManager != true || user?.canCreateTransactions == true) add(Tab.SCAN)
            add(Tab.MEMBERS); add(Tab.HISTORY); add(Tab.SETTINGS)
        }
    }
    var selected by rememberSaveable { mutableStateOf(tabs.first()) }
    if (selected !in tabs) selected = tabs.first()

    Scaffold(bottomBar = {
        NavigationBar {
            tabs.forEach { tab ->
                NavigationBarItem(
                    selected = tab == selected, onClick = { selected = tab }, label = { Text(tab.title) },
                    icon = {
                        val badge = if (tab == Tab.HISTORY) snapshot.pendingCount + snapshot.rejectedCount else 0
                        if (badge > 0) BadgedBox(badge = { Badge { Text("$badge") } }) { Icon(tab.icon, tab.title) } else Icon(tab.icon, tab.title)
                    },
                )
            }
        }
    }) { inner ->
        Box(Modifier.padding(inner)) {
            when (selected) {
                Tab.PLATFORM -> PlatformScreen(model)
                Tab.HOME -> DashboardScreen(model)
                Tab.SCAN -> ScanScreen(model)
                Tab.MEMBERS -> MembersScreen(model)
                Tab.HISTORY -> HistoryScreen(model)
                Tab.SETTINGS -> SettingsScreen(model)
            }
        }
    }
}

@Composable
private fun BlockedScreen(model: AppModel, message: String) {
    Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Filled.Lock, null, Modifier.size(56.dp), tint = Brand.orange)
        Spacer(Modifier.height(20.dp))
        Text(message, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        Spacer(Modifier.height(12.dp))
        Text("العمليات المسجلة على هذا الجهاز محفوظة وستُرسل تلقائياً بعد إعادة التفعيل.", textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(20.dp))
        Button(onClick = { model.syncSoon() }) { Text("إعادة المحاولة") }
        TextButton(onClick = { model.logout() }) { Text("تسجيل الخروج", color = Color.Red) }
    }
}

/** Covers the app until the platform owner passes biometrics / device PIN. */
@Composable
private fun LockScreen(model: AppModel, authenticate: ((String?) -> Unit) -> Unit) {
    var error by remember { mutableStateOf<String?>(null) }
    val ask = { authenticate { result -> if (result == null) model.unlocked() else error = result } }
    LaunchedEffect(Unit) { ask() }
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(32.dp),
        verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Filled.Fingerprint, null, Modifier.size(72.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(16.dp))
        Text("حساب صاحب المنصة", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text("التطبيق مقفل. تحقق بالبصمة أو رمز الجوال للمتابعة.", textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
        error?.let { Spacer(Modifier.height(8.dp)); Text(it, color = Color.Red, textAlign = TextAlign.Center) }
        Spacer(Modifier.height(20.dp))
        Button(onClick = ask, modifier = Modifier.fillMaxWidth(0.7f)) { Text("فتح") }
        TextButton(onClick = { model.logout() }) { Text("تسجيل الخروج", color = Color.Red) }
    }
}

/** Platform announcement, same tones as the website's modal. */
@Composable
private fun SystemMessageDialog(model: AppModel, message: SystemMessage) {
    val (color, icon) = when (message.tone) {
        SystemMessage.Tone.SUCCESS -> Brand.green to Icons.Filled.CheckCircle
        SystemMessage.Tone.WARNING -> Brand.orange to Icons.Filled.Warning
        SystemMessage.Tone.DANGER -> Color(0xFFE53935) to Icons.Filled.Error
        SystemMessage.Tone.INFO -> Color(0xFF1E88E5) to Icons.Filled.Campaign
    }
    AlertDialog(
        onDismissRequest = { if (!message.isForced) model.dismiss(message) },
        properties = DialogProperties(dismissOnBackPress = !message.isForced, dismissOnClickOutside = !message.isForced),
        icon = { Box(Modifier.size(64.dp).background(color, CircleShape), contentAlignment = Alignment.Center) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(34.dp)) } },
        title = { Text(message.title, textAlign = TextAlign.Center, fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth()) },
        text = { Text(message.body, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) },
        confirmButton = {
            Button(onClick = { model.acknowledge(message) }, colors = ButtonDefaults.buttonColors(containerColor = color), modifier = Modifier.fillMaxWidth()) { Text("فهمت") }
        },
        dismissButton = {
            if (!message.isForced) TextButton(onClick = { model.dismiss(message) }, modifier = Modifier.fillMaxWidth()) { Text("إغلاق") }
        },
    )
}
