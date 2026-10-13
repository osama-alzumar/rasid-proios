import UIKit
import RasidKit
import SwiftUI

/// Earn or redeem form. The fields follow the shop's reward type exactly like
/// the website's cashier screen (RewardRules.formSpec).
struct TransactionSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let member: Member
    let type: TransactionType
    let onDone: (String) -> Void

    @State private var amount = ""
    @State private var count = ""
    @State private var invoice = ""
    @State private var serviceId: Int?
    @State private var vehicleId: Int?
    @State private var error: String?
    @State private var isSaving = false

    private var shop: Shop? { model.shop }
    private var services: [Service] { model.snapshot.services.filter(\.isActive) }

    var body: some View {
        NavigationStack {
            Form {
                if let shop {
                    let spec = RewardRules.formSpec(shop: shop, type: type, hasService: serviceId != nil)
                    let preview = evaluate(shop: shop)

                    Section {
                        LabeledContent("العميل", value: member.name)
                        LabeledContent("الرصيد الحالي", value: "\(model.balance(of: member))")
                    }

                    if type == .earn && !services.isEmpty {
                        Section("الخدمة") {
                            Picker("الخدمة", selection: $serviceId) {
                                Text("بدون خدمة").tag(Int?.none)
                                ForEach(services) { service in
                                    Text(service.price.map { "\(service.name) — \(Formatting.amount($0)) ر.س" } ?? service.name).tag(Int?.some(service.id))
                                }
                            }
                        }
                    }

                    if type == .earn && shop.vehicleModuleEnabled && !member.vehicles.isEmpty {
                        Section("السيارة") {
                            Picker("السيارة", selection: $vehicleId) {
                                Text("بدون").tag(Int?.none)
                                ForEach(member.vehicles) { Text($0.plateText).tag(Int?.some($0.id)) }
                            }
                        }
                    }

                    if spec.showsAmount || spec.showsInvoice || spec.showsCount {
                        Section {
                            if spec.showsAmount {
                                numberField(spec.amountRequired ? "قيمة الفاتورة (ر.س)" : "قيمة الفاتورة (اختياري)", text: $amount, decimal: true)
                            }
                            if spec.showsInvoice {
                                TextField(spec.invoiceRequired ? "رقم الفاتورة" : "رقم الفاتورة (اختياري)", text: $invoice)
                                    .keyboardType(.asciiCapable)
                                    .autocorrectionDisabled()
                            }
                            if spec.showsCount {
                                numberField(countLabel(shop), text: $count, decimal: false)
                            }
                        } footer: {
                            if let min = shop.minStampAmount, type == .earn, shop.rewardType == .stamps {
                                Text("يُحتسب الختم للفواتير من \(Formatting.amount(min)) ريال فأكثر.")
                            }
                        }
                    }

                    Section {
                        switch preview {
                        case .success(let change):
                            Label(previewText(shop: shop, change: change), systemImage: type == .earn ? "plus.circle" : "minus.circle")
                                .foregroundStyle(type == .earn ? Theme.brandDeep : .orange)
                                .font(.headline)
                        case .failure(let failure):
                            if hasInput || type == .redeem {
                                Label(failure.message, systemImage: "info.circle").foregroundStyle(.secondary)
                            }
                        }
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(type == .earn ? "عملية إضافة" : "استبدال مكافأة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تأكيد", action: save)
                        .fontWeight(.bold)
                        .disabled(isSaving || shop.map { (try? evaluate(shop: $0).get()) == nil } ?? true)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var hasInput: Bool { !amount.isEmpty || !count.isEmpty || !invoice.isEmpty || serviceId != nil }

    private func numberField(_ title: String, text: Binding<String>, decimal: Bool) -> some View {
        TextField(title, text: text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .environment(\.layoutDirection, .rightToLeft)
    }

    private func countLabel(_ shop: Shop) -> String {
        switch (shop.rewardType, type) {
        case (.points, _): return "عدد النقاط المستبدلة"
        case (.stamps, _): return "عدد الأختام (افتراضي ١)"
        case (.visits, _): return "عدد الزيارات المضافة"
        }
    }

    private func previewText(shop: Shop, change: Int) -> String {
        let unit: String
        switch shop.rewardType {
        case .points: unit = "نقطة"
        case .stamps: unit = change == 1 ? "ختم" : "أختام"
        case .visits: unit = "زيارة"
        }
        return type == .earn ? "سيُضاف \(change) \(unit)" : "سيُخصم \(change) \(unit)"
    }

    private func draft() -> TransactionDraft {
        TransactionDraft(memberId: member.id, type: type,
                         amount: Self.number(amount),
                         count: Self.number(count).map { Int($0) },
                         invoiceNo: invoice.isEmpty ? nil : invoice,
                         vehicleId: vehicleId, serviceId: serviceId)
    }

    private func evaluate(shop: Shop) -> Result<Int, RewardRuleError> {
        let service = serviceId.flatMap { id in services.first { $0.id == id } }
        return RewardRules.evaluate(draft(), shop: shop, balance: model.balance(of: member), service: service)
    }

    /// Accepts Arabic-Indic digits and the Arabic decimal separator.
    static func number(_ text: String) -> Double? {
        let map: [Character: Character] = ["٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4", "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9", "٫": ".", ",": "."]
        let normalized = String(text.map { map[$0] ?? $0 }).trimmingCharacters(in: .whitespaces)
        return normalized.isEmpty ? nil : Double(normalized)
    }

    private func save() {
        guard let shop else { return }
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                let op = try await model.record(draft())
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onDone(previewText(shop: shop, change: op.pointsChange).replacingOccurrences(of: "سيُضاف", with: "تمت إضافة").replacingOccurrences(of: "سيُخصم", with: "تم خصم"))
                dismiss()
            } catch let failure as RewardRuleError {
                error = failure.message
            } catch let apiError as APIError {
                error = apiError.message
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
