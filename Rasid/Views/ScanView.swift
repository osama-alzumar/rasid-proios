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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SyncStatusBar()
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
        .task {
            if CameraAccess.status == .notDetermined {
                cameraAllowed = await CameraAccess.request()
                cameraDenied = !cameraAllowed
            }
        }
    }

    @ViewBuilder
    private var scannerArea: some View {
        ZStack {
            if cameraAllowed && !model.isDemo {
                CodeScannerView(isActive: found == nil && !showAddMember && !isLooking) { code in
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
                found = try await model.findMember(code: trimmed)
                manualCode = ""
            } catch let apiError as APIError {
                error = apiError == .offline ? "العميل غير موجود في النسخة المحفوظة ولا يوجد اتصال للبحث في الخادم." : apiError.message
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
