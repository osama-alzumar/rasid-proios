import RasidKit
import SwiftUI
import UIKit

/// Compose and send a message to every customer who added the shop's card to
/// Apple Wallet. It replaces the "store message" on the card, and Wallet shows
/// it as a lock-screen notification.
struct StoreMessageView: View {
    @EnvironmentObject private var model: AppModel
    @State private var text = ""
    @State private var confirm = false
    @State private var isSending = false
    @State private var result: String?
    @State private var error: String?
    @FocusState private var editing: Bool

    /// Lock-screen banners show roughly the first 150 characters.
    private let recommended = 150
    private let maximum = 1000

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var reach: WalletReach? { model.snapshot.walletReach }

    var body: some View {
        Form {
            Section {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("مثال: عرض نهاية الأسبوع — القهوة الثانية مجاناً حتى الأحد ☕")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.horizontal, 4)
                    }
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .focused($editing)
                        .onChange(of: text) { _, new in
                            if new.count > maximum { text = String(new.prefix(maximum)) }
                        }
                }
                HStack {
                    Text("\(trimmed.count) / \(maximum)")
                        .monospacedDigit()
                        .foregroundStyle(trimmed.count > recommended ? .orange : .secondary)
                    Spacer()
                    if trimmed.count > recommended {
                        Text("الإشعار يعرض أول \(recommended) حرف تقريباً").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
            } header: {
                Text("الرسالة")
            } footer: {
                Text("تظهر كإشعار على شاشة القفل عند العملاء، وتبقى مكتوبة خلف بطاقتهم في المحفظة حتى ترسل رسالة جديدة.")
            }

            if !trimmed.isEmpty {
                Section("كيف تظهر عند العميل") {
                    NotificationPreview(shopName: model.shop?.name ?? "رصيد", message: trimmed)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                if let reach {
                    LabeledContent("عملاء أضافوا البطاقة", value: "\(reach.cards)")
                    LabeledContent("أجهزة تستقبل الإشعار", value: "\(reach.devices)")
                }
                if let current = model.shop?.storeMessage, !current.isEmpty {
                    LabeledContent("الرسالة الحالية على البطاقة") {
                        Text(current).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                }
            } header: {
                Text("المستلمون")
            } footer: {
                Text("يصل الإشعار لمن أضاف البطاقة إلى Apple Wallet وفعّل التحديثات التلقائية لها.")
            }

            if let result {
                Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.brandDeep)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }

            Section {
                Button {
                    editing = false
                    confirm = true
                } label: {
                    HStack {
                        Spacer()
                        if isSending { ProgressView().padding(.trailing, 6) }
                        Label(isSending ? "جارٍ الإرسال…" : "إرسال للعملاء", systemImage: "paperplane.fill").fontWeight(.bold)
                        Spacer()
                    }
                }
                .disabled(trimmed.isEmpty || isSending || !model.isOnline)
            } footer: {
                if !model.isOnline {
                    Text("الإرسال يحتاج اتصالاً بالإنترنت.").foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("رسالة للعملاء")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(confirmTitle, isPresented: $confirm, titleVisibility: .visible) {
            Button("إرسال") { send() }
        } message: {
            Text("ستحل محل الرسالة الحالية على بطاقات العملاء.")
        }
    }

    private var confirmTitle: String {
        if let devices = reach?.devices, devices > 0 { return "إرسال الرسالة إلى \(devices) جهاز؟" }
        return "إرسال الرسالة لكل العملاء؟"
    }

    private func send() {
        isSending = true
        error = nil
        result = nil
        Task {
            defer { isSending = false }
            do {
                let sent = try await model.sendStoreMessage(trimmed)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                result = sent.map { "تم الإرسال. تصل الرسالة إلى \($0.devices) جهاز خلال دقائق." } ?? "تم الإرسال."
                text = ""
            } catch let apiError as APIError {
                error = apiError == .offline ? "تعذر الاتصال. لم تُرسل الرسالة، حاول مرة أخرى." : apiError.message
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Mock of the Wallet lock-screen banner.
private struct NotificationPreview: View {
    let shopName: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .padding(5)
                .frame(width: 38, height: 38)
                .background(Color(red: 0.043, green: 0.071, blue: 0.125), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(shopName).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("الآن").font(.caption).foregroundStyle(.secondary)
                }
                Text(message)
                    .font(.subheadline)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("معاينة الإشعار: \(shopName)، \(message)")
    }
}
