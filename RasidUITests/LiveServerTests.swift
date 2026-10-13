import XCTest

/// End-to-end against the real rasid.pro API with the App Review demo cashier
/// (isolated demo shop). Runs only when CI provides the credentials through
/// TEST_RUNNER_RASID_E2E_EMAIL / _PASSWORD, and only on iPhone so one run adds
/// exactly one stamp. CI resets the demo shop afterwards.
final class LiveServerTests: XCTestCase {
    func testCashierAddsStampOnLiveServer() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["RASID_E2E_EMAIL"], let password = env["RASID_E2E_PASSWORD"], !email.isEmpty else {
            throw XCTSkip("No live-server credentials")
        }
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone only") }
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments = ["-hasLaunchedBefore", "NO", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()

        let emailField = app.textFields["البريد الإلكتروني"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10))
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["كلمة المرور"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["تسجيل الدخول"].tap()

        // Fresh install on the scan tab asks for the camera; decline it.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 8) {
            springboard.alerts.firstMatch.buttons.element(boundBy: 0).tap()
        }

        let search = app.textFields["رقم الجوال أو رقم البطاقة"]
        XCTAssertTrue(search.waitForExistence(timeout: 20), "logged in and on the scan tab")
        search.tap()
        search.typeText("0500000101")
        app.buttons["بحث"].tap()

        XCTAssertTrue(app.staticTexts["سارة العتيبي"].waitForExistence(timeout: 15), "customer found")
        XCTAssertTrue(labelContaining("4 / 6", in: app).waitForExistence(timeout: 5), "demo starting balance")
        attach(app, "live-01-member")

        app.buttons["إضافة ختم"].tap()
        let invoice = app.textFields["رقم الفاتورة"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 5))
        invoice.tap()
        invoice.typeText("E2E-CI")
        app.buttons["تأكيد"].tap()

        XCTAssertTrue(labelContaining("5 / 6", in: app).waitForExistence(timeout: 10), "balance updated on screen")
        attach(app, "live-02-after-stamp")

        // The operation must leave the outbox: History shows nothing pending.
        let history = app.tabBars.buttons["السجل"]
        history.tap()
        XCTAssertTrue(app.staticTexts["آخر العمليات"].waitForExistence(timeout: 5))
        let pending = app.staticTexts["بانتظار الإرسال"]
        let sent = NSPredicate(format: "exists == false")
        expectation(for: sent, evaluatedWith: pending)
        waitForExpectations(timeout: 30)
        XCTAssertTrue(app.staticTexts["سارة العتيبي"].waitForExistence(timeout: 10), "server transaction listed")
        attach(app, "live-03-history")
    }

    /// The balance card combines its texts into one accessibility element.
    private func labelContaining(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
