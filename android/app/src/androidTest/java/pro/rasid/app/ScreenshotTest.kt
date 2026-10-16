package pro.rasid.app

import android.content.Intent
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.FileInputStream

/**
 * Drives the app in demo mode (debug-only sample shop, no network) through the
 * main screens. CI pulls the PNGs as a visual check and for the download page.
 */
@RunWith(AndroidJUnit4::class)
class ScreenshotTest {
    @get:Rule val compose = createEmptyComposeRule()
    private var scenario: ActivityScenario<MainActivity>? = null

    private fun launch(vararg extras: Pair<String, Any>) {
        val app = ApplicationProvider.getApplicationContext<RasidApplication>()
        app.model = null // each test starts from a fresh demo model
        val intent = Intent(app, MainActivity::class.java).putExtra("demo", true)
        extras.forEach { (k, v) -> when (v) { is Boolean -> intent.putExtra(k, v); is String -> intent.putExtra(k, v) } }
        scenario = ActivityScenario.launch(intent)
        compose.waitForIdle()
    }

    @After fun close() { scenario?.close() }

    /** screencap runs as the shell user, so the files outlive the app's uninstall after the run. */
    private fun snap(name: String) {
        compose.waitForIdle()
        Thread.sleep(400) // let ripples / sheet animations settle
        shell("mkdir -p /sdcard/rasid-shots")
        shell("screencap -p /sdcard/rasid-shots/$name.png")
    }

    private fun shell(command: String) {
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use { fd ->
            FileInputStream(fd.fileDescriptor).use { it.readBytes() } // wait for completion
        }
    }

    private fun tab(title: String) = compose.onNode(hasText(title) and hasClickAction())

    @Test fun cashierFlow() {
        launch()
        compose.onNodeWithTag("search").assertExists()
        snap("01-scan")
        tab("العملاء").performClick()
        compose.waitUntil(5000) { compose.onAllNodes(hasText("سارة العتيبي")).fetchSemanticsNodes().isNotEmpty() }
        snap("02-members")
        compose.onNodeWithText("سارة العتيبي").performClick()
        compose.onNodeWithText("الرصيد الحالي").assertExists()
        compose.onNodeWithText("4 / 6").assertExists()
        snap("03-member")
        compose.onNodeWithTag("earn").performClick()
        compose.onNodeWithTag("invoice").performTextInput("1024")
        compose.onNodeWithText("سيُضاف 1 ختم").assertExists()
        snap("04-earn")
        compose.onNodeWithTag("confirm").performClick()
        compose.waitUntil(5000) { compose.onAllNodes(hasText("تمت إضافة 1 ختم")).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("5 / 6").assertExists()
        snap("05-after-stamp")
        tab("السجل").performClick()
        compose.onNodeWithText("آخر العمليات").assertExists()
        snap("06-history")
        tab("الإعدادات").performClick()
        compose.onNodeWithText("المظهر").assertExists()
        snap("07-settings")
    }

    @Test fun merchantSendsStoreMessage() {
        launch("role" to "manager")
        compose.onNodeWithTag("compose").assertExists()
        snap("08-merchant-home")
        compose.onNodeWithTag("compose").performClick()
        compose.onNodeWithTag("message").performTextInput("عرض نهاية الأسبوع: القهوة الثانية مجاناً")
        compose.onNodeWithText("كيف تظهر عند العميل").assertExists()
        snap("09-store-message")
    }

    @Test fun systemMessageShowsAndAcknowledges() {
        launch("systemMessage" to true)
        compose.onNodeWithText("تحديث مهم").assertExists()
        snap("10-system-message")
        compose.onNodeWithText("إغلاق").assertDoesNotExist()
        compose.onNodeWithText("فهمت").performClick()
        compose.waitUntil(5000) { compose.onAllNodes(hasText("تحديث مهم")).fetchSemanticsNodes().isEmpty() }
    }
}
