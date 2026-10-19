import CoreImage.CIFilterBuiltins
import RasidKit
import SwiftUI
import UIKit

/// The shop's self-scan QR: hung at the counter, customers scan it with the
/// phone camera and get one stamp (or point) a day without the cashier.
struct SelfScanView: View {
    @EnvironmentObject private var model: AppModel
    @State private var settings: SelfScanSettings?
    @State private var isBusy = false
    @State private var error: String?
    @State private var confirmNewCode = false

    private var unit: String { model.shop?.rewardType == .points ? "نقطة" : "ختم" }

    var body: some View {
        Form {
            if let settings {
                if !settings.available {
                    Section {
                        Label("محلات الزيارات لا تدعم المسح الذاتي، لأن الزيارة رصيد مدفوع مسبقاً.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Toggle(isOn: Binding(get: { settings.enabled }, set: { update(enabled: $0) })) {
                            Label("تشغيل باركود المحل", systemImage: "qrcode")
                        }
                        .disabled(isBusy)
                    } footer: {
                        Text("العميل يصوّر الباركود بكاميرا جواله، يكتب رقمه أول مرة فقط، وينضاف له \(unit) واحد. الحد: \(unit) واحد لكل عميل في اليوم.")
                    }

                    if settings.enabled, let url = settings.url {
                        Section {
                            VStack(spacing: 12) {
                                if let image = QRCode.image(for: url) {
                                    Image(uiImage: image)
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: 260)
                                        .padding(12)
                                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                                        .accessibilityLabel("باركود المحل")
                                }
                                Text(model.shop?.name ?? "")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }

                        Section {
                            if let poster = settings.posterURL.flatMap(URL.init(string:)) {
                                ShareLink(item: poster) {
                                    Label("مشاركة ملصق الطباعة", systemImage: "square.and.arrow.up")
                                }
                                Link(destination: poster) {
                                    Label("فتح ملصق الطباعة", systemImage: "printer")
                                }
                            }
                            Button(role: .destructive) {
                                confirmNewCode = true
                            } label: {
                                Label("تغيير الباركود", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(isBusy)
                        } footer: {
                            Text("علّق الملصق داخل المحل فقط. إذا انتشرت صورة الباركود، غيّره ويتوقف القديم.")
                        }
                    }
                }
            } else if error == nil {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Button("إعادة المحاولة") { Task { await load() } }
                }
            }
        }
        .navigationTitle("باركود المسح الذاتي")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("تغيير الباركود؟", isPresented: $confirmNewCode, titleVisibility: .visible) {
            Button("تغيير الباركود", role: .destructive) { update(enabled: true, newCode: true) }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("الباركود القديم والملصقات المطبوعة تتوقف، ولازم تطبع الملصق الجديد.")
        }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do { settings = try await model.selfScan() } catch { self.error = Self.message(error) }
    }

    private func update(enabled: Bool, newCode: Bool = false) {
        isBusy = true
        error = nil
        Task {
            defer { isBusy = false }
            do {
                settings = try await model.setSelfScan(enabled: enabled, newCode: newCode)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                self.error = Self.message(error)
            }
        }
    }

    private static func message(_ error: Error) -> String {
        (error as? APIError)?.message ?? error.localizedDescription
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
