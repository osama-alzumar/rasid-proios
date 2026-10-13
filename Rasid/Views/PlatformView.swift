import RasidKit
import SwiftUI

/// Super admin home: whole-platform numbers plus the shop picker. Choosing a
/// shop switches the other tabs (scan, customers, history) to that shop.
struct PlatformView: View {
    @EnvironmentObject private var model: AppModel
    @State private var period = "today"
    @State private var stats: PlatformStats?
    @State private var shops: [Shop] = []
    @State private var search = ""
    @State private var error: String?
    @State private var switching: Int?

    var body: some View {
        List {
            Section {
                SyncStatusBar()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                Picker("الفترة", selection: $period) {
                    Text("اليوم").tag("today")
                    Text("٧ أيام").tag("week")
                    Text("٣٠ يوماً").tag("month")
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let stats {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        StatTile(title: "المحلات", metric: stats.shops, symbol: "building.2.fill")
                        StatTile(title: "اشتراكات فعالة", metric: stats.activeSubscriptions, symbol: "checkmark.seal.fill")
                        StatTile(title: "العملاء", metric: stats.customers, symbol: "person.2.fill")
                        StatTile(title: "العمليات", metric: stats.transactions, symbol: "arrow.left.arrow.right")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            if let top = stats?.topActiveShops, !top.isEmpty {
                Section("الأكثر نشاطاً") {
                    ForEach(top, id: \.id) { shop in
                        HStack {
                            Text(shop.name)
                            Spacer()
                            Text("\(shop.transactionsCount) عملية").foregroundStyle(.secondary).font(.footnote)
                        }
                    }
                }
            }

            Section {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                ForEach(shops, id: \.id) { shop in
                    Button {
                        select(shop)
                    } label: {
                        ShopRow(shop: shop, isCurrent: shop.id == model.snapshot.selectedShopId, isSwitching: switching == shop.id)
                    }
                    .disabled(switching != nil)
                }
            } header: {
                Text("المحلات")
            } footer: {
                Text("اختر محلاً لتعمل عليه من تبويبات المسح والعملاء والسجل، كأنك كاشير فيه.")
            }
        }
        .navigationTitle("المنصة")
        .searchable(text: $search, prompt: "ابحث باسم المحل")
        .refreshable { await load() }
        .task(id: period) { await loadStats() }
        .task(id: search) {
            try? await Task.sleep(for: .milliseconds(350))
            await loadShops()
        }
    }

    private func load() async {
        await loadStats()
        await loadShops()
    }

    private func loadStats() async {
        do {
            stats = try await model.platformStats(period: period)
        } catch let apiError as APIError {
            error = apiError.message
        } catch {}
    }

    private func loadShops() async {
        do {
            shops = try await model.shops(search: search)
            error = nil
        } catch let apiError as APIError {
            error = apiError.message
        } catch {}
    }

    private func select(_ shop: Shop) {
        switching = shop.id
        Task {
            defer { switching = nil }
            do {
                try await model.selectShop(shop)
            } catch let apiError as APIError {
                error = apiError.message
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct ShopRow: View {
    let shop: Shop
    let isCurrent: Bool
    let isSwitching: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background((shop.isExpired ? Color.gray : Theme.brand).gradient, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(shop.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(shop.isExpired ? .red : .secondary)
            }
            Spacer()
            if isSwitching {
                ProgressView()
            } else if isCurrent {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.brand)
            }
        }
    }

    private var icon: String {
        switch shop.rewardType {
        case .points: return "star.fill"
        case .stamps: return "seal.fill"
        case .visits: return "car.fill"
        }
    }

    private var detail: String {
        let type: String
        switch shop.rewardType {
        case .points: type = "نقاط"
        case .stamps: type = "أختام"
        case .visits: type = "زيارات"
        }
        let members = shop.membersCount.map { " · \($0) عميل" } ?? ""
        return shop.isExpired ? "منتهي الاشتراك · \(type)" : "\(type)\(members)"
    }
}
