import Charts
import RasidKit
import SwiftUI

/// Merchant overview (GET /dashboard/stats). Needs a connection; the last
/// result stays on screen when offline.
struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var period = "today"
    @State private var stats: DashboardStats?
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SyncStatusBar()
                Picker("الفترة", selection: $period) {
                    Text("اليوم").tag("today")
                    Text("٧ أيام").tag("week")
                    Text("٣٠ يوماً").tag("month")
                }
                .pickerStyle(.segmented)

                if let error, stats == nil {
                    ContentUnavailableView("تعذر تحميل الإحصائيات", systemImage: "chart.bar.xaxis", description: Text(error))
                }

                if let stats {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        StatTile(title: "العملاء", metric: stats.customers, symbol: "person.2.fill")
                        StatTile(title: "عملاء جدد", metric: stats.newCustomers, symbol: "person.badge.plus")
                        StatTile(title: "العمليات", metric: stats.transactions, symbol: "arrow.left.arrow.right")
                        StatTile(title: "الاستبدالات", metric: stats.redemptions, symbol: "gift.fill")
                    }
                    chart(stats)
                    activities(stats)
                } else if isLoading {
                    ProgressView().padding(40)
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(model.shop?.name ?? "الرئيسية")
        .refreshable { await load() }
        .task(id: period) { await load() }
    }

    private func load() async {
        guard !model.isDemo else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            stats = try await model.dashboard(period: period)
            error = nil
        } catch let apiError as APIError {
            error = apiError.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func chart(_ stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("النشاط").font(.headline)
            Chart(Array(stats.activityChart.enumerated()), id: \.offset) { item in
                BarMark(x: .value("الوقت", item.offset), y: .value("العدد", item.element.earnCount))
                    .foregroundStyle(by: .value("النوع", "إضافة"))
                BarMark(x: .value("الوقت", item.offset), y: .value("العدد", item.element.redeemCount))
                    .foregroundStyle(by: .value("النوع", "استبدال"))
            }
            .chartForegroundStyleScale(["إضافة": Theme.brand, "استبدال": Color.orange])
            .chartXAxis(.hidden)
            .frame(height: 180)
        }
        .cardStyle()
    }

    private func activities(_ stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("آخر النشاطات").font(.headline)
            if stats.recentActivities.isEmpty {
                Text("لا يوجد نشاط بعد").foregroundStyle(.secondary)
            }
            ForEach(Array(stats.recentActivities.enumerated()), id: \.offset) { item in
                let activity = item.element
                HStack {
                    Image(systemName: icon(activity.type)).foregroundStyle(Theme.brand)
                    VStack(alignment: .leading) {
                        Text(activity.memberName ?? "—").font(.subheadline.weight(.semibold))
                        Text(label(activity)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func icon(_ type: String) -> String {
        switch type {
        case "new_member": return "person.badge.plus"
        case "reward_redeemed": return "gift.fill"
        default: return "plus.circle.fill"
        }
    }

    private func label(_ activity: DashboardStats.Activity) -> String {
        switch activity.type {
        case "new_member": return "عميل جديد"
        case "reward_redeemed": return "استبدال \(activity.amount ?? 0)"
        default: return "إضافة \(activity.amount ?? 0)"
        }
    }
}

struct StatTile: View {
    let title: String
    let metric: DashboardStats.Metric
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text("\(metric.value)").font(.system(.title, design: .rounded).weight(.bold))
            if let trend = metric.trend {
                Text("\(trend >= 0 ? "▲" : "▼") \(abs(trend), specifier: "%.1f")٪")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(trend >= 0 ? Theme.brandDeep : .red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
