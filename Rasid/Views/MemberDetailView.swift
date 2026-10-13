import RasidKit
import SwiftUI

struct MemberDetailView: View {
    @EnvironmentObject private var model: AppModel
    let memberId: Int
    @State private var sheet: TransactionType?
    @State private var showAddVehicle = false
    @State private var confirmation: String?

    var body: some View {
        Group {
            if let member = model.member(id: memberId), let shop = model.shop {
                content(member: member, shop: shop)
            } else {
                ContentUnavailableView("العميل غير موجود", systemImage: "person.crop.circle.badge.questionmark",
                                       description: Text("ربما حُذف من لوحة التحكم."))
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("العميل")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(member: Member, shop: Shop) -> some View {
        let balance = model.balance(of: member)
        let summary = BalanceSummary.make(shop: shop, balance: balance)
        let pending = model.snapshot.pendingDelta(memberId: member.id)
        let canTransact = model.user?.canCreateTransactions == true

        return ScrollView {
            VStack(spacing: 16) {
                SyncStatusBar()

                VStack(spacing: 6) {
                    Text(member.name)
                        .font(.title2.weight(.bold))
                    HStack(spacing: 12) {
                        if let phone = member.phone {
                            Label(phone, systemImage: "phone.fill")
                        }
                        if let code = member.externalId {
                            Label(code, systemImage: "creditcard.fill")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .cardStyle()

                BalanceCard(summary: summary, shop: shop, balance: balance, pendingDelta: pending)

                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.brandDeep)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Theme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity)
                }

                if canTransact {
                    HStack(spacing: 12) {
                        actionButton(earnTitle(shop), "plus.circle.fill", Theme.brand) { sheet = .earn }
                        actionButton("استبدال", "gift.fill", .orange) { sheet = .redeem }
                            .disabled(!summary.rewardAvailable)
                    }
                }

                if shop.vehicleModuleEnabled {
                    vehicles(member)
                }

                history(member)
            }
            .padding()
        }
        .sheet(item: $sheet) { type in
            TransactionSheet(member: member, type: type) { message in
                withAnimation { confirmation = message }
            }
        }
        .sheet(isPresented: $showAddVehicle) {
            AddVehicleView(memberId: member.id)
        }
    }

    private func earnTitle(_ shop: Shop) -> String {
        switch shop.rewardType {
        case .points: return "إضافة نقاط"
        case .stamps: return "إضافة ختم"
        case .visits: return "تسجيل زيارة"
        }
    }

    private func actionButton(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.subheadline.weight(.bold))
            }
            .frame(maxWidth: .infinity, minHeight: 84)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func vehicles(_ member: Member) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("السيارات").font(.headline)
                Spacer()
                if model.user?.canCreateVehicles == true {
                    Button {
                        showAddVehicle = true
                    } label: {
                        Label("إضافة", systemImage: "plus")
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            if member.vehicles.isEmpty {
                Text("لا توجد سيارات مسجلة").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(member.vehicles) { vehicle in
                HStack {
                    PlateView(vehicle: vehicle)
                    Spacer()
                    Text(vehicle.descriptionText).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }

    private func history(_ member: Member) -> some View {
        let pending = model.snapshot.pending.filter { $0.draft.memberId == member.id }
        let recent = model.snapshot.recentTransactions.filter { $0.memberId == member.id }.prefix(10)
        return VStack(alignment: .leading, spacing: 10) {
            Text("آخر العمليات").font(.headline)
            if pending.isEmpty && recent.isEmpty {
                Text("لا توجد عمليات حديثة على هذا الجهاز").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(pending) { PendingRow(op: $0) }
            ForEach(Array(recent)) { TransactionRow(transaction: $0, showMember: false) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

extension TransactionType: @retroactive Identifiable {
    public var id: String { rawValue }
}

struct BalanceCard: View {
    let summary: BalanceSummary
    let shop: Shop
    let balance: Int
    let pendingDelta: Int

    var body: some View {
        VStack(spacing: 12) {
            Text("الرصيد الحالي")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.headline)
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .environment(\.layoutDirection, .leftToRight)
                Text(summary.unit).font(.title3.weight(.semibold))
            }
            .foregroundStyle(.white)
            if shop.rewardType == .stamps {
                StampsRow(filled: min(max(balance, 0), shop.stampsPerReward), total: shop.stampsPerReward)
            }
            if let detail = summary.detail {
                Text(detail).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            }
            if pendingDelta != 0 {
                Label("يشمل \(pendingDelta > 0 ? "+" : "")\(pendingDelta) بانتظار الإرسال", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            if let message = shop.storeMessage, !message.isEmpty {
                Text(message).font(.footnote).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(
            LinearGradient(colors: [Theme.brand, Theme.brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

struct StampsRow: View {
    let filled: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Image(systemName: index < filled ? "checkmark.seal.fill" : "seal")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(index < filled ? 1 : 0.5))
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

struct PlateView: View {
    let vehicle: Vehicle

    var body: some View {
        HStack(spacing: 6) {
            Text(vehicle.plateLettersAr ?? "")
            Divider().frame(height: 18)
            Text(vehicle.plateNumber ?? "").monospacedDigit()
        }
        .font(.subheadline.weight(.bold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.6), lineWidth: 1.5))
    }
}
