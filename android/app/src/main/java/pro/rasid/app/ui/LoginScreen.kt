package pro.rasid.app.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import pro.rasid.app.AppModel
import pro.rasid.app.R
import pro.rasid.core.ApiError

/** One sign-in screen for merchants, cashiers and the platform owner. */
@Composable
fun LoginScreen(model: AppModel) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var show by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val submit = {
        if (email.isNotBlank() && password.isNotEmpty() && !loading) {
            loading = true; error = null
            scope.launch {
                try { model.login(email, password) } catch (e: ApiError) { error = e.message } catch (e: Exception) { error = e.localizedMessage }
                loading = false
            }
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Spacer(Modifier.height(56.dp))
        Image(painterResource(R.drawable.logo), null, Modifier.size(84.dp))
        Text("رصيد", fontSize = 34.sp, fontWeight = FontWeight.Black)
        Text("دخول التاجر والكاشير", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(email, { email = it }, Modifier.fillMaxWidth().testTag("email"), label = { Text("البريد الإلكتروني") },
            leadingIcon = { Icon(Icons.Filled.Email, null, tint = Brand.green) }, singleLine = true, shape = RoundedCornerShape(14.dp),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Next))
        // KeyboardType.Password opens a Latin keyboard even on an Arabic phone.
        OutlinedTextField(password, { password = it }, Modifier.fillMaxWidth().testTag("password"), label = { Text("كلمة المرور") },
            leadingIcon = { Icon(Icons.Filled.Lock, null, tint = Brand.green) }, singleLine = true, shape = RoundedCornerShape(14.dp),
            visualTransformation = if (show) VisualTransformation.None else PasswordVisualTransformation(),
            trailingIcon = { IconButton(onClick = { show = !show }) { Icon(if (show) Icons.Filled.VisibilityOff else Icons.Filled.Visibility, if (show) "إخفاء كلمة المرور" else "إظهار كلمة المرور") } },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Go),
            keyboardActions = KeyboardActions(onGo = { submit() }))
        error?.let { Text(it, color = Color(0xFFE53935), modifier = Modifier.fillMaxWidth()) }
        Button(onClick = submit, enabled = !loading && email.isNotBlank() && password.isNotEmpty(),
            modifier = Modifier.fillMaxWidth().height(52.dp).testTag("login"), shape = RoundedCornerShape(14.dp)) {
            if (loading) CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp) else Text("تسجيل الدخول", fontWeight = FontWeight.Bold)
        }
        Text("تبقى مسجلاً على هذا الجهاز حتى تختار تسجيل الخروج.", fontSize = 13.sp, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
