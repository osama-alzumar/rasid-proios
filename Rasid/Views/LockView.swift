import SwiftUI

/// Covers the whole app until the platform owner passes Face ID / passcode.
struct LockView: View {
    @EnvironmentObject private var model: AppModel
    @State private var error: String?
    @State private var isChecking = false

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "faceid")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.brand)
                Text("حساب صاحب المنصة")
                    .font(.title2.weight(.bold))
                Text("التطبيق مقفل. تحقق ببصمة الوجه أو رمز الجوال للمتابعة.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let error {
                    Text(error).font(.footnote.weight(.medium)).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button(action: unlock) {
                    Label("فتح", systemImage: "lock.open.fill")
                        .frame(maxWidth: 260, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isChecking)
                Button("تسجيل الخروج", role: .destructive) { Task { await model.logout() } }
                    .font(.footnote)
            }
            .padding(32)
        }
        .task { unlock() }
    }

    private func unlock() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            error = await model.unlock()
            isChecking = false
        }
    }
}
