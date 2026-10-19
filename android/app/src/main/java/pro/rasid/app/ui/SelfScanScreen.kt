package pro.rasid.app.ui

import android.content.Intent
import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlinx.coroutines.launch
import pro.rasid.app.AppModel
import pro.rasid.core.ApiError
import pro.rasid.core.RewardType
import pro.rasid.core.SelfScanSettings

/**
 * The shop's self-scan QR: hung at the counter, customers scan it with the
 * phone camera and get one stamp (or point) a day without the cashier.
 */
@Composable
fun SelfScanScreen(model: AppModel, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    var settings by remember { mutableStateOf<SelfScanSettings?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmNewCode by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val uri = LocalUriHandler.current
    val context = LocalContext.current
    val unit = if (model.shop?.rewardType == RewardType.POINTS) "نقطة" else "ختم"

    suspend fun run(block: suspend () -> SelfScanSettings) {
        busy = true; error = null
        try { settings = block() } catch (e: ApiError) { error = if (e is ApiError.Offline) "تعذر الاتصال. تحقق من الإنترنت وحاول مرة أخرى." else e.message }
        busy = false
    }
    LaunchedEffect(Unit) { run { model.selfScan() } }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ScreenScaffoldTitle("باركود المسح الذاتي", onClose)
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            val s = settings
            when {
                s == null && error == null -> CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally))
                s != null && !s.available -> Text("محلات الزيارات لا تدعم المسح الذاتي، لأن الزيارة رصيد مدفوع مسبقاً.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                s != null -> {
                    RasidCard {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("تشغيل باركود المحل", Modifier.weight(1f), fontWeight = FontWeight.Bold)
                            Switch(s.enabled, { on -> scope.launch { run { model.setSelfScan(on) } } }, Modifier.testTag("selfScanSwitch"),
                                enabled = !busy, colors = SwitchDefaults.colors(checkedTrackColor = Brand.green))
                        }
                        Text("العميل يصوّر الباركود بكاميرا جواله، يكتب رقمه أول مرة فقط، وينضاف له $unit واحد. الحد: $unit واحد لكل عميل في اليوم.",
                            fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    val url = s.url
                    if (s.enabled && url != null) {
                        val qr = remember(url) { qrBitmap(url) }
                        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                            Image(qr.asImageBitmap(), "باركود المحل", Modifier.size(260.dp).background(Color.White, RoundedCornerShape(16.dp)).padding(12.dp),
                                filterQuality = FilterQuality.None)
                            Spacer(Modifier.height(8.dp))
                            Text(model.shop?.name ?: "", fontWeight = FontWeight.Bold)
                        }
                        s.posterUrl?.let { poster ->
                            OutlinedButton(onClick = {
                                context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, poster), "مشاركة ملصق الطباعة"))
                            }, Modifier.fillMaxWidth()) { Icon(Icons.Filled.Share, null); Spacer(Modifier.width(8.dp)); Text("مشاركة ملصق الطباعة") }
                            OutlinedButton(onClick = { uri.openUri(poster) }, Modifier.fillMaxWidth()) { Icon(Icons.Filled.Print, null); Spacer(Modifier.width(8.dp)); Text("فتح ملصق الطباعة") }
                        }
                        TextButton(onClick = { confirmNewCode = true }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                            Icon(Icons.Filled.Refresh, null, tint = Color(0xFFE53935)); Spacer(Modifier.width(8.dp)); Text("تغيير الباركود", color = Color(0xFFE53935))
                        }
                        Text("علّق الملصق داخل المحل فقط. إذا انتشرت صورة الباركود، غيّره ويتوقف القديم.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            error?.let {
                Text(it, color = Color(0xFFE53935))
                TextButton(onClick = { scope.launch { run { model.selfScan() } } }) { Text("إعادة المحاولة") }
            }
        }
    }
    if (confirmNewCode) AlertDialog(onDismissRequest = { confirmNewCode = false },
        title = { Text("تغيير الباركود؟") },
        text = { Text("الباركود القديم والملصقات المطبوعة تتوقف، ولازم تطبع الملصق الجديد.") },
        confirmButton = { TextButton(onClick = { confirmNewCode = false; scope.launch { run { model.setSelfScan(true, newCode = true) } } }) { Text("تغيير الباركود", color = Color(0xFFE53935)) } },
        dismissButton = { TextButton(onClick = { confirmNewCode = false }) { Text("إلغاء") } })
}

private fun qrBitmap(text: String, size: Int = 600): Bitmap {
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 1))
    val pixels = IntArray(size * size) { i -> if (matrix[i % size, i / size]) android.graphics.Color.BLACK else android.graphics.Color.WHITE }
    return Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
}
