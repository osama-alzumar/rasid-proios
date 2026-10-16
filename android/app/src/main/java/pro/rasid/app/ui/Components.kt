package pro.rasid.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import pro.rasid.app.AppModel
import pro.rasid.core.BalanceSummary
import pro.rasid.core.PendingOperation
import pro.rasid.core.ServerTransaction
import pro.rasid.core.Shop
import pro.rasid.core.TxType
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun RasidCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(modifier.fillMaxWidth(), shape = Brand.cardShape, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.padding(16.dp), content = content)
    }
}

/** Numbers like "4 / 6" read left-to-right even inside the RTL layout. */
@Composable
fun Ltr(content: @Composable () -> Unit) = CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr, content = content)

@Composable
fun SyncStatusBar(model: AppModel) {
    val online by model.isOnline.collectAsState()
    val snapshot by model.snapshot.collectAsState()
    if (model.isDemo) return
    val (text, icon, color) = when {
        !online -> Triple("وضع عدم الاتصال — العمليات تُحفظ وتُرسل لاحقاً", Icons.Filled.WifiOff, Brand.orange)
        snapshot.pendingCount > 0 -> Triple("بانتظار الإرسال: ${snapshot.pendingCount}", Icons.Filled.Sync, Color(0xFF1E88E5))
        snapshot.rejectedCount > 0 -> Triple("عمليات رفضها الخادم: ${snapshot.rejectedCount} — راجع السجل", Icons.Filled.Warning, Color(0xFFE53935))
        else -> return
    }
    Row(Modifier.fillMaxWidth().background(color.copy(alpha = 0.12f), RoundedCornerShape(12.dp)).padding(vertical = 8.dp, horizontal = 12.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = color, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(6.dp))
        Text(text, color = color, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
    }
}

@Composable
fun BalanceCard(summary: BalanceSummary, shop: Shop, pendingDelta: Int) {
    Column(Modifier.fillMaxWidth().background(Brush.linearGradient(listOf(Brand.greenBright, Brand.green)), RoundedCornerShape(24.dp)).padding(22.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("الرصيد الحالي", color = Color.White.copy(alpha = 0.85f))
        Row(verticalAlignment = Alignment.Bottom) {
            Ltr { Text(summary.headline, color = Color.White, fontSize = 46.sp, fontWeight = FontWeight.Black) }
            Spacer(Modifier.width(8.dp)); Text(summary.unit, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
        }
        if (summary.total != null && summary.filled != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                repeat(summary.total!!) { i ->
                    Icon(if (i < summary.filled!!) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null, tint = Color.White.copy(alpha = if (i < summary.filled!!) 1f else 0.5f))
                }
            }
        }
        summary.detail?.let { Text(it, color = Color.White, fontWeight = FontWeight.SemiBold) }
        if (pendingDelta != 0) Text("يشمل ${if (pendingDelta > 0) "+" else ""}$pendingDelta بانتظار الإرسال", color = Color.White.copy(alpha = 0.9f), fontSize = 12.sp)
        shop.storeMessage?.takeIf { it.isNotBlank() }?.let { Text(it, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, textAlign = TextAlign.Center) }
    }
}

@Composable
fun PendingRow(op: PendingOperation) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(if (op.rejected) Icons.Filled.Cancel else Icons.Filled.Schedule, null, tint = if (op.rejected) Color(0xFFE53935) else Color(0xFF1E88E5))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(op.memberName, fontWeight = FontWeight.SemiBold)
            Text(if (op.rejected) op.lastError ?: "رفضها الخادم" else SimpleDateFormat("d MMM HH:mm", Locale("ar")).format(Date(op.createdAtMillis)),
                fontSize = 12.sp, color = if (op.rejected) Color(0xFFE53935) else MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Ltr {
            Text("${if (op.draft.type == TxType.EARN) "+" else "−"}${op.pointsChange}", fontWeight = FontWeight.Bold,
                color = if (op.rejected) Color.Gray else if (op.draft.type == TxType.EARN) Brand.green else Brand.orange,
                textDecoration = if (op.rejected) TextDecoration.LineThrough else null)
        }
    }
}

@Composable
fun TransactionRow(tx: ServerTransaction, showMember: Boolean) {
    val earn = tx.type == TxType.EARN
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(if (earn) Icons.Filled.AddCircle else Icons.Filled.CardGiftcard, null, tint = if (earn) Brand.green else Brand.orange)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            if (showMember) Text(tx.memberName ?: "—", fontWeight = FontWeight.SemiBold)
            val date = tx.createdAt?.split(" ")?.let { if (it.size == 2) "${it[0].drop(5)} ${it[1].take(5)}" else tx.createdAt }
            Text(listOfNotNull(tx.serviceName, tx.invoiceNo?.let { "فاتورة $it" }, tx.createdBy, date).joinToString(" · "), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Ltr { Text("${if (earn) "+" else "−"}${kotlin.math.abs(tx.pointsChange)}", fontWeight = FontWeight.Bold, color = if (earn) Brand.green else Brand.orange) }
    }
}

@Composable
fun Avatar(name: String) {
    Text(name.take(1), color = Color.White, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
        modifier = Modifier.size(40.dp).background(Brand.green, CircleShape).padding(top = 8.dp))
}

@Composable
fun StatTile(title: String, value: Int, trend: Double?, icon: ImageVector, modifier: Modifier = Modifier) {
    RasidCard(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(6.dp))
            Text(title, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
        }
        Text("$value", fontSize = 28.sp, fontWeight = FontWeight.Bold)
        trend?.let { Text("${if (it >= 0) "▲" else "▼"} ${"%.1f".format(kotlin.math.abs(it))}٪", color = if (it >= 0) Brand.green else Color(0xFFE53935), fontSize = 12.sp, fontWeight = FontWeight.SemiBold) }
    }
}

@Composable
fun PlateChip(letters: String?, number: String?) {
    Row(Modifier.border(1.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), RoundedCornerShape(6.dp)).padding(horizontal = 10.dp, vertical = 4.dp)) {
        Text(letters.orEmpty(), fontWeight = FontWeight.Bold); Spacer(Modifier.width(8.dp)); Text(number.orEmpty(), fontWeight = FontWeight.Bold)
    }
}
