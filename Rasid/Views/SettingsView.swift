import RasidKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @State private var confirmLogout = false

    var body: some View {
        Form {
            if let user = model.user {
                Section("الحساب") {
                    LabeledContent("الاسم", value: user.name)
                    LabeledContent("البريد", value: user.email)
                    LabeledContent("الصلاحية", value: user.isSuperAdmin ? "مدير النظام" : (user.isManager ? "مدير المحل" : "كاشير"))
                    if let shop = model.shop {
                        LabeledContent("المحل", value: shop.name)
                        if let expires = shop.expiresAt {
                            LabeledContent("ينتهي الاشتراك", value: expires)
                        }
                    }
                }
            }

            Section("المظهر") {
                Picker("المظهر", selection: $appearance) {
                    ForEach(Appearance.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                LabeledContent("الاتصال", value: model.isOnline ? "متصل" : "غير متصل")
                LabeledContent("العملاء على الجهاز", value: "\(model.snapshot.members.count)")
                LabeledContent("بانتظار الإرسال", value: "\(model.snapshot.pendingCount)")
                if let last = model.snapshot.lastSuccessfulSync {
                    LabeledContent("آخر مزامنة", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                if let error = model.lastSyncError {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
                Button {
                    Task { await model.syncNow() }
                } label: {
                    HStack {
                        Text("مزامنة الآن")
                        Spacer()
                        if model.isSyncing { ProgressView() }
                    }
                }
                .disabled(model.isSyncing)
            } header: {
                Text("المزامنة")
            } footer: {
                Text("يحتفظ التطبيق بنسخة من بيانات المحل ليعمل بدون إنترنت، ويرسل العمليات تلقائياً عند عودة الاتصال.")
            }

            Section {
                Link(destination: URL(string: "https://info.rasid.pro/privacy-policy/")!) {
                    Label("سياسة الخصوصية", systemImage: "hand.raised.fill")
                }
                Link(destination: URL(string: "https://info.rasid.pro/")!) {
                    Label("موقع رصيد", systemImage: "globe")
                }
            }

            Section {
                Button("تسجيل الخروج", role: .destructive) { confirmLogout = true }
            } footer: {
                Text("الإصدار \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            }
        }
        .navigationTitle("الإعدادات")
        .confirmationDialog(logoutWarning, isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("تسجيل الخروج", role: .destructive) { Task { await model.logout() } }
        }
    }

    private var logoutWarning: String {
        let pending = model.snapshot.pendingCount
        return pending > 0
            ? "يوجد \(pending) عملية لم تُرسل بعد وستُحذف من الجهاز عند الخروج. انتظر حتى تتم المزامنة إن أمكن."
            : "هل تريد تسجيل الخروج من هذا الجهاز؟"
    }
}
