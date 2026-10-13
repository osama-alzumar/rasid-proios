import LocalAuthentication

enum DeviceAuth {
    enum Outcome: Equatable {
        case success
        case failure(String)
    }

    /// Face ID / Touch ID, falling back to the device passcode.
    static func authenticate(reason: String) async -> Outcome {
        let context = LAContext()
        context.localizedCancelTitle = "إلغاء"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode at all: the owner account must not open unprotected.
            return .failure("فعّل رمز قفل الجوال من الإعدادات لاستخدام حساب صاحب المنصة على هذا الجهاز.")
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return .success
        } catch {
            return .failure("لم يتم التحقق. حاول مرة أخرى.")
        }
    }
}
