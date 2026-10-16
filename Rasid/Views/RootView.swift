import RasidKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .loggedOut:
                LoginView()
            case .loggedIn:
                if let message = model.blockingMessage {
                    BlockedView(message: message)
                } else {
                    MainTabView()
                }
            }
        }
        .animation(.default, value: model.phase)
        .sheet(item: Binding(
            get: { model.isLocked ? nil : model.systemMessages.first },
            set: { if $0 == nil, let shown = model.systemMessages.first, !shown.isForced { model.dismissSystemMessage(shown) } }
        )) { message in
            SystemMessageView(message: message)
        }
    }
}

/// Shown when the server says the shop subscription ended or the account was
/// disabled. Renewal happens with the Rasid team outside the app.
struct BlockedView: View {
    @EnvironmentObject private var model: AppModel
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text(message)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("العمليات المسجلة على هذا الجهاز محفوظة وستُرسل تلقائياً بعد إعادة التفعيل.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("إعادة المحاولة") { model.syncSoon() }
                .buttonStyle(.borderedProminent)
            Button("تسجيل الخروج", role: .destructive) { Task { await model.logout() } }
            Spacer()
        }
        .padding(32)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            if model.user?.isSuperAdmin == true {
                NavigationStack { PlatformView() }
                    .tabItem { Label("المنصة", systemImage: "building.2.fill") }
            }
            if model.needsShopSelection {
                NavigationStack { SettingsView() }
                    .tabItem { Label("الإعدادات", systemImage: "gearshape.fill") }
            } else {
                shopTabs
            }
        }
    }

    @ViewBuilder
    private var shopTabs: some View {
        if model.user?.isManager == true {
            NavigationStack { DashboardView() }
                .tabItem { Label("الرئيسية", systemImage: "chart.bar.xaxis") }
        }
        if model.user?.isManager != true || model.user?.canCreateTransactions == true {
            NavigationStack { ScanView() }
                .tabItem { Label("المسح", systemImage: "qrcode.viewfinder") }
        }
        NavigationStack { MembersListView() }
            .tabItem { Label("العملاء", systemImage: "person.2.fill") }
        NavigationStack { HistoryView() }
            .tabItem { Label("السجل", systemImage: "clock.arrow.circlepath") }
            .badge(model.snapshot.pendingCount + model.snapshot.rejectedCount)
        NavigationStack { SettingsView() }
            .tabItem { Label("الإعدادات", systemImage: "gearshape.fill") }
    }
}

/// Thin status strip shown at the top of the main screens.
struct SyncStatusBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.isDemo {
            EmptyView()
        } else if !model.isOnline {
            label("وضع عدم الاتصال — العمليات تُحفظ وتُرسل لاحقاً", "wifi.slash", .orange)
        } else if model.snapshot.pendingCount > 0 {
            label("بانتظار الإرسال: \(model.snapshot.pendingCount)", "arrow.triangle.2.circlepath", .blue)
        } else if model.snapshot.rejectedCount > 0 {
            label("عمليات رفضها الخادم: \(model.snapshot.rejectedCount) — راجع السجل", "exclamationmark.triangle.fill", .red)
        }
    }

    private func label(_ text: String, _ symbol: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
