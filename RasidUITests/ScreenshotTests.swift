import XCTest

/// Drives the app in demo mode (`-RasidDemo`, DEBUG only — no network, sample
/// shop) through the main screens. CI exports the attachments as App Store
/// screenshots and as a visual check that each screen renders.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-RasidDemo", "-hasLaunchedBefore", "YES"] + extra
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
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        snap(app, "01-scan")

        tabs.buttons["العملاء"].tap()
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

        tabs.buttons["السجل"].tap()
        XCTAssertTrue(app.staticTexts["آخر العمليات"].waitForExistence(timeout: 5))
        snap(app, "05-history")

        tabs.buttons["الإعدادات"].tap()
        XCTAssertTrue(app.staticTexts["المظهر"].waitForExistence(timeout: 5))
        snap(app, "06-settings")
    }

    func testDarkModeScreens() {
        let app = launch(["-appearance", "dark"])
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons["العملاء"].tap()
        let member = app.staticTexts["خالد الشهري"]
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        member.tap()
        XCTAssertTrue(app.staticTexts["المكافأة جاهزة للاستبدال"].waitForExistence(timeout: 5))
        snap(app, "07-member-dark")
    }

    func testLoginScreen() {
        let app = XCUIApplication()
        // No demo flag and a fresh install: the sign-in screen must appear.
        app.launchArguments = ["-hasLaunchedBefore", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["دخول التاجر والكاشير"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["تسجيل الدخول"].exists)
        snap(app, "00-login")
    }
}
