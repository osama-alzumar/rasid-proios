package pro.rasid.app

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import pro.rasid.app.ui.RasidRoot
import pro.rasid.core.Role

class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as RasidApplication
        // Demo mode (sample shop, no network) exists only in debug builds, for CI screenshots.
        val demo = BuildConfig.DEBUG && intent.getBooleanExtra("demo", false)
        val existing = app.model
        val model = existing ?: AppModel.create(this, demo, if (intent.getStringExtra("role") == "manager") Role.SHOP_MANAGER else Role.CASHIER).also { app.model = it }
        if (existing == null) {
            if (demo && intent.getBooleanExtra("systemMessage", false)) model.showDemoSystemMessage()
            // App-level foreground/background (survives activity recreation, registered once).
            ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
                override fun onStart(owner: LifecycleOwner) { model.syncSoon(); model.fetchSystemMessagesIfNeeded() }
                override fun onStop(owner: LifecycleOwner) = model.lockIfNeeded()
            })
        }

        setContent { RasidRoot(model, ::authenticate) }
    }

    /** Biometrics with the device PIN/pattern as fallback; null = success, else the error text. */
    private fun authenticate(onResult: (String?) -> Unit) {
        val authenticators = BIOMETRIC_WEAK or DEVICE_CREDENTIAL
        if (BiometricManager.from(this).canAuthenticate(authenticators) != BiometricManager.BIOMETRIC_SUCCESS) {
            // No screen lock at all: the owner account must not open unprotected.
            onResult("فعّل قفل الشاشة (بصمة أو رمز) في إعدادات الجوال لاستخدام حساب صاحب المنصة على هذا الجهاز.")
            return
        }
        val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) = onResult(null)
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) = onResult("لم يتم التحقق. حاول مرة أخرى.")
        })
        prompt.authenticate(BiometricPrompt.PromptInfo.Builder()
            .setTitle("حساب صاحب المنصة")
            .setSubtitle("تحقق بالبصمة أو رمز الجوال للمتابعة")
            .setAllowedAuthenticators(authenticators)
            .build())
    }
}
