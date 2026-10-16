package pro.rasid.app.ui

import android.Manifest
import android.content.pm.PackageManager
import android.view.HapticFeedbackConstants
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import kotlinx.coroutines.launch
import pro.rasid.app.AppModel
import pro.rasid.core.ApiError
import pro.rasid.core.Member
import java.util.concurrent.Executors

/** Cashier home: scan the customer's card or type their phone / card number. */
@Composable
fun ScanScreen(model: AppModel) {
    var opened by remember { mutableStateOf<Member?>(null) }
    var adding by remember { mutableStateOf(false) }
    opened?.let { MemberDetailScreen(model, it.id) { opened = null }; return }
    if (adding) { AddMemberScreen(model, onDone = { m -> adding = false; opened = m }, onCancel = { adding = false }); return }

    val context = LocalContext.current
    var granted by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted = it }
    LaunchedEffect(Unit) { if (!granted && !model.isDemo) launcher.launch(Manifest.permission.CAMERA) }

    var code by remember { mutableStateOf("") }
    var looking by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val lookup: (String) -> Unit = { raw ->
        val c = raw.trim()
        if (c.isNotEmpty() && !looking) {
            looking = true; error = null
            scope.launch {
                try { opened = model.findMember(c); code = "" }
                catch (e: ApiError) { error = if (e is ApiError.Offline) "العميل غير موجود في النسخة المحفوظة ولا يوجد اتصال للبحث في الخادم." else e.message }
                looking = false
            }
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(model.shop?.name ?: "المسح", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        SyncStatusBar(model)
        Box(Modifier.fillMaxWidth().height(320.dp).background(Color.Black, RoundedCornerShape(24.dp)), contentAlignment = Alignment.Center) {
            if (granted && !model.isDemo && !looking) CameraScanner(onCode = lookup)
            else Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Filled.QrCodeScanner, null, tint = Color.White.copy(alpha = 0.8f), modifier = Modifier.size(48.dp))
                Spacer(Modifier.height(8.dp))
                Text(if (granted || model.isDemo) "وجّه الكاميرا إلى رمز بطاقة العميل" else "اسمح باستخدام الكاميرا لمسح بطاقة العميل", color = Color.White, textAlign = TextAlign.Center)
            }
            Box(Modifier.fillMaxSize().padding(36.dp).border(4.dp, Brand.greenBright, RoundedCornerShape(24.dp)))
            if (looking) CircularProgressIndicator(color = Color.White)
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(code, { code = it }, Modifier.weight(1f).testTag("search"), label = { Text("رقم الجوال أو رقم البطاقة") }, singleLine = true,
                shape = RoundedCornerShape(14.dp), keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { lookup(code) }))
            Spacer(Modifier.width(8.dp))
            Button(onClick = { lookup(code) }, enabled = code.isNotBlank() && !looking) { Text("بحث") }
        }
        error?.let { Text(it, color = Color(0xFFE53935)) }
        if (model.user?.canCreateMembers == true) {
            OutlinedButton(onClick = { adding = true }, modifier = Modifier.fillMaxWidth().height(48.dp)) {
                Icon(Icons.Filled.PersonAdd, null); Spacer(Modifier.width(8.dp)); Text("تسجيل عميل جديد")
            }
        }
    }
}

/** Live camera + ML Kit for the code on the customer's Wallet card (QR, Code 128, PDF417, Aztec). */
@Composable
private fun CameraScanner(onCode: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current
    val view = LocalView.current
    val executor = remember { Executors.newSingleThreadExecutor() }
    val scanner = remember {
        BarcodeScanning.getClient(BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE, Barcode.FORMAT_CODE_128, Barcode.FORMAT_PDF417, Barcode.FORMAT_AZTEC, Barcode.FORMAT_EAN_13, Barcode.FORMAT_CODE_39)
            .build())
    }
    var last by remember { mutableStateOf("" to 0L) }
    DisposableEffect(Unit) { onDispose { scanner.close(); executor.shutdown() } }
    AndroidView(factory = { ctx ->
        val previewView = PreviewView(ctx)
        val providerFuture = ProcessCameraProvider.getInstance(ctx)
        providerFuture.addListener({
            val provider = providerFuture.get()
            val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
            val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
            analysis.setAnalyzer(executor) { proxy ->
                val media = proxy.image
                if (media == null) { proxy.close(); return@setAnalyzer }
                scanner.process(InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees))
                    .addOnSuccessListener { codes ->
                        val value = codes.firstNotNullOfOrNull { it.rawValue?.takeIf(String::isNotBlank) }
                        val now = System.currentTimeMillis()
                        // The same card stays in frame for a while: report it once.
                        if (value != null && !(value == last.first && now - last.second < 3000)) {
                            last = value to now
                            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                            onCode(value)
                        }
                    }
                    .addOnCompleteListener { proxy.close() }
            }
            runCatching {
                provider.unbindAll()
                provider.bindToLifecycle(lifecycle, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
            }
        }, ContextCompat.getMainExecutor(ctx))
        previewView
    }, modifier = Modifier.fillMaxSize())
}
