import XCTest

/// Drives the app in demo mode (`-RasidDemo`, DEBUG only — no network, sample
/// shop) through the main screens. CI exports the attachments as App Store
/// screenshots and as a visual check that each screen renders.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Run the system UI (alerts, keyboard, status bar) in Arabic as well.
    private let arabic = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]

    /// iPhone shows a bottom tab bar; iPadOS 18+ shows the tabs as a floating
    /// bar at the top, which is not exposed as `tabBars`.
    private func tab(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let inTabBar = app.tabBars.buttons[title]
        return inTabBar.exists ? inTabBar : app.buttons[title].firstMatch
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-RasidDemo", "-hasLaunchedBefore", "YES"] + arabic + extra
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCashierFlow() {
        let app = launch()
        XCTAssertTrue(tab(app, "العملاء").waitForExistence(timeout: 10))
        snap(app, "01-scan")

        tab(app, "العملاء").tap()
        let member = app.staticTexts["سارة العتيبي"]
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        snap(app, "02-members")

        member.tap()
        XCTAssertTrue(app.staticTexts["الرصيد الحالي"].waitForExistence(timeout: 5))
        snap(app, "03-member")

        app.buttons["إضافة ختم"].tap()
        XCTAssertTrue(app.navigationBars["عملية إضافة"].waitForExistence(timeout: 5))
        snap(app, "04-earn")
        app.buttons["إلغاء"].tap()

        tab(app, "السجل").tap()
        XCTAssertTrue(app.staticTexts["آخر العمليات"].waitForExistence(timeout: 5))
        snap(app, "05-history")

        tab(app, "الإعدادات").tap()
        XCTAssertTrue(app.staticTexts["المظهر"].waitForExistence(timeout: 5))
        snap(app, "06-settings")
    }

    func testDarkModeScreens() {
        let app = launch(["-appearance", "dark"])
        XCTAssertTrue(tab(app, "العملاء").waitForExistence(timeout: 10))
        tab(app, "العملاء").tap()
        let member = app.staticTexts["خالد الشهري"]
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        member.tap()
        XCTAssertTrue(app.staticTexts["المكافأة جاهزة للاستبدال"].waitForExistence(timeout: 5))
        snap(app, "07-member-dark")
    }

    func testLoginScreen() {
        let app = XCUIApplication()
        // No demo flag and a fresh install: the sign-in screen must appear.
        app.launchArguments = ["-hasLaunchedBefore", "NO"] + arabic
        app.launch()
        XCTAssertTrue(app.staticTexts["دخول التاجر والكاشير"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["تسجيل الدخول"].exists)
        snap(app, "00-login")
    }

    func testMerchantSendsStoreMessage() {
        let app = launch(["-RasidManager"])
        let compose = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "رسالة للعملاء")).firstMatch
        XCTAssertTrue(compose.waitForExistence(timeout: 10), "merchant home offers the customer message")
        snap(app, "08-merchant-home")
        compose.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("عرض نهاية الأسبوع: القهوة الثانية مجاناً")
        XCTAssertTrue(app.staticTexts["كيف تظهر عند العميل"].waitForExistence(timeout: 5), "live lock-screen preview")
        snap(app, "09-store-message")
    }
}

