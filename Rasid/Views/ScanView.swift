import AVFoundation
import RasidKit
import SwiftUI
import UIKit

/// Cashier home: scan the customer's card or type their number/ID.
struct ScanView: View {
    @EnvironmentObject private var model: AppModel
    @State private var cameraAllowed = CameraAccess.status == .authorized
    @State private var cameraDenied = CameraAccess.status == .denied || CameraAccess.status == .restricted
    @State private var manualCode = ""
    @State private var isLooking = false
    @State private var error: String?
    @State private var found: Member?
    @State private var showAddMember = false
    @FocusState private var manualFocused: Bool
    /// Quick scan: scanning a card adds one stamp straight away.
    @AppStorage("quickScanEnabled") private var quickScanEnabled = true
    @State private var quickResult: QuickResult?
    @State private var repeatCandidate: Member?
    @State private var lastQuickAdd: [Int: Date] = [:]

    private var quickScanAvailable: Bool {
        guard let shop = model.shop, model.user?.canCreateTransactions == true else { return false }
        return RewardRules.supportsQuickScan(shop)
    }

    private var quickScanOn: Bool { quickScanAvailable && quickScanEnabled }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SyncStatusBar()
                if quickScanAvailable {
                    Toggle(isOn: $quickScanEnabled) {
                        Label("إضافة ختم تلقائياً عند المسح", systemImage: "bolt.badge.checkmark")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(Theme.brand)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                }
                if let quickResult {
                    QuickResultBanner(result: quickResult) {
                        found = quickResult.member
                        self.quickResult = nil
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                scannerArea
                manualEntry
                if let error {
                    Label(error, systemImage: "person.fill.questionmark")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.user?.canCreateMembers == true {
                    Button {
                        showAddMember = true
                    } label: {
                        Label("تسجيل عميل جديد", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(model.shop?.name ?? "المسح")
        .navigationDestination(item: $found) { member in
            MemberDetailView(memberId: member.id)
        }
        .sheet(isPresented: $showAddMember) {
            AddMemberView { member in found = member }
        }
        .confirmationDialog(repeatTitle, isPresented: Binding(get: { repeatCandidate != nil }, set: { if !$0 { repeatCandidate = nil } }), titleVisibility: .visible) {
            if let member = repeatCandidate {
                Button("إضافة ختم آخر") { addQuickStamp(to: member, allowRepeat: true) }
                Button("فتح ملف العميل") { found = member }
            }
            Button("إلغاء", role: .cancel) {}
        }
        .animation(.spring(duration: 0.35), value: quickResult)
        .task {
            if CameraAccess.status == .notDetermined && !model.isDemo {
                cameraAllowed = await CameraAccess.request()
                cameraDenied = !cameraAllowed
            }
        }
    }

    @ViewBuilder
    private var scannerArea: some View {
        ZStack {
            if cameraAllowed && !model.isDemo {
                CodeScannerView(isActive: found == nil && !showAddMember && !isLooking && repeatCandidate == nil) { code in
                    lookup(code)
                }
            } else {
                Color.black.opacity(0.85)
                VStack(spacing: 12) {
                    Image(systemName: cameraDenied ? "camera.badge.ellipsis" : "qrcode.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.8))
                    if cameraDenied {
                        Text("اسمح باستخدام الكاميرا لمسح بطاقة العميل")
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Button("فتح الإعدادات") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("وجّه الكاميرا إلى رمز بطاقة العميل")
                            .foregroundStyle(.white)
                    }
                }
                .padding()
            }
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Theme.brand, style: StrokeStyle(lineWidth: 4, dash: [28, 14]))
                .padding(36)
                .allowsHitTesting(false)
            if isLooking {
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ماسح بطاقة العميل")
    }

    private var manualEntry: some View {
        HStack(spacing: 10) {
            Image(systemName: "number")
                .foregroundStyle(Theme.brand)
            TextField("رقم الجوال أو رقم البطاقة", text: $manualCode)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($manualFocused)
                .submitLabel(.search)
                .onSubmit { lookup(manualCode) }
            Button("بحث") { lookup(manualCode) }
                .buttonStyle(.borderedProminent)
                .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty || isLooking)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 54)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func lookup(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLooking else { return }
        manualFocused = false
        isLooking = true
        error = nil
        Task {
            defer { isLooking = false }
            do {
                let member = try await model.findMember(code: trimmed)
                manualCode = ""
                if quickScanOn {
                    addQuickStamp(to: member, allowRepeat: false)
                } else {
                    found = member
                }
            } catch let apiError as APIError {
                error = apiError == .offline ? "العميل غير موجود في النسخة المحفوظة ولا يوجد اتصال للبحث في الخادم." : apiError.message
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

    private var repeatTitle: String {
        guard let member = repeatCandidate, let at = lastQuickAdd[member.id] else { return "" }
        let seconds = max(1, Int(Date().timeIntervalSince(at)))
        let ago = seconds < 60 ? "قبل \(seconds) ثانية" : "قبل دقيقة"
        return "أُضيف ختم لـ \(member.name) \(ago)"
    }

    /// One stamp per scan. The same card held in front of the camera is
    /// ignored for a few seconds, and a second scan within two minutes asks
    /// first, so a customer is never stamped twice by accident.
    private func addQuickStamp(to member: Member, allowRepeat: Bool) {
        guard let shop = model.shop else { found = member; return }
        if !allowRepeat, let at = lastQuickAdd[member.id] {
            let elapsed = Date().timeIntervalSince(at)
            if elapsed < 10 { return }
            if elapsed < 120 { repeatCandidate = member; return }
        }
        switch RewardRules.quickScan(memberId: member.id, shop: shop, balance: model.balance(of: member)) {
        case .notSupported:
            found = member
        case .rewardReady:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            found = member
        case .add(let draft):
            Task {
                do {
                    try await model.record(draft)
                    lastQuickAdd[member.id] = Date()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    let balance = model.balance(of: member)
                    let result = QuickResult(member: member, balance: balance, total: shop.stampsPerReward)
                    quickResult = result
                    try? await Task.sleep(for: .seconds(6))
                    if quickResult == result { quickResult = nil }
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
}

struct QuickResult: Equatable {
    let id = UUID()
    let member: Member
    let balance: Int
    let total: Int

    var rewardReady: Bool { balance >= total }
}

/// Big confirmation after a quick-scan stamp, readable at arm's length.
private struct QuickResultBanner: View {
    let result: QuickResult
    let openMember: () -> Void

    var body: some View {
        Button(action: openMember) {
            HStack(spacing: 14) {
                Image(systemName: result.rewardReady ? "gift.fill" : "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 4) {
                    Text("تمت إضافة ختم")
                        .font(.headline)
                    Text(result.member.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text("الأختام \(result.balance) / \(result.total)" + (result.rewardReady ? " — المكافأة جاهزة" : ""))
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.left")
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
            .background(result.rewardReady ? Color.orange : Theme.brandDeep, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("تمت إضافة ختم لـ \(result.member.name)، الأختام \(result.balance) من \(result.total)")
    }
}
