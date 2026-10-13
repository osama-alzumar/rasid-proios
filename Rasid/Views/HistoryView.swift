import RasidKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var toDiscard: PendingOperation?

    var body: some View {
        List {
            let rejected = model.snapshot.pending.filter { $0.status == .rejected }
            let pending = model.snapshot.pending.filter { $0.status == .pending }

            if !rejected.isEmpty {
                Section {
                    ForEach(rejected) { op in
                        PendingRow(op: op)
                            .swipeActions { Button("حذف", role: .destructive) { toDiscard = op } }
                    }
                } header: {
                    Text("رفضها الخادم")
                } footer: {
                    Text("هذه العمليات لم تُحتسب. غالباً تغيّر رصيد العميل من جهاز آخر قبل الإرسال. افتح العميل وأعد العملية إن لزم، ثم احذفها من هنا.")
                }
            }

            if !pending.isEmpty {
                Section {
                    ForEach(pending) { PendingRow(op: $0) }
                } header: {
                    Text("بانتظار الإرسال")
                } footer: {
                    Text("تُرسل تلقائياً عند توفر الاتصال.")
                }
            }

            Section("آخر العمليات") {
                if model.snapshot.recentTransactions.isEmpty {
                    Text("لا توجد عمليات بعد").foregroundStyle(.secondary)
                }
                ForEach(model.snapshot.recentTransactions) { TransactionRow(transaction: $0, showMember: true) }
            }
        }
        .navigationTitle("السجل")
        .refreshable { await model.syncNow() }
        .confirmationDialog("حذف العملية المرفوضة؟", isPresented: Binding(get: { toDiscard != nil }, set: { if !$0 { toDiscard = nil } }), titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                if let op = toDiscard { Task { await model.discard(op) } }
            }
        }
    }
}

struct PendingRow: View {
    let op: PendingOperation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: op.status == .rejected ? "xmark.octagon.fill" : "clock.fill")
                .foregroundStyle(op.status == .rejected ? .red : .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(op.memberName).font(.subheadline.weight(.semibold))
                Text(op.status == .rejected ? (op.lastError ?? "رفضها الخادم") : op.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(op.status == .rejected ? .red : .secondary)
            }
            Spacer()
            Text("\(op.draft.type == .earn ? "+" : "−")\(op.pointsChange)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(op.status == .rejected ? .secondary : (op.draft.type == .earn ? Theme.brandDeep : .orange))
                .strikethrough(op.status == .rejected)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}

struct TransactionRow: View {
    let transaction: ServerTransaction
    let showMember: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.type == .earn ? "plus.circle.fill" : "gift.fill")
                .foregroundStyle(transaction.type == .earn ? Theme.brand : .orange)
            VStack(alignment: .leading, spacing: 2) {
                if showMember { Text(transaction.memberName ?? "—").font(.subheadline.weight(.semibold)) }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(transaction.type == .earn ? "+" : "−")\(abs(transaction.pointsChange))")
                .font(.headline.monospacedDigit())
                .foregroundStyle(transaction.type == .earn ? Theme.brandDeep : .orange)
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    private var subtitle: String {
        [transaction.serviceName, transaction.invoiceNo.map { "فاتورة \($0)" }, transaction.createdBy, transaction.createdAt.map(Self.shortDate)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private static func shortDate(_ raw: String) -> String {
        // Server format "Y-m-d H:i:s" in the shop's local time.
        let parts = raw.split(separator: " ")
        guard parts.count == 2 else { return raw }
        return "\(parts[0].dropFirst(5)) \(parts[1].prefix(5))"
    }
}
