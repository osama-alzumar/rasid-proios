import RasidKit
import SwiftUI

/// Registering a customer needs the server (it issues the card number and the
/// Wallet pass), so this form is online-only and says so.
struct AddMemberView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let onCreated: (Member) -> Void

    @State private var name = ""
    @State private var phone = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("اسم العميل", text: $name)
                        .textContentType(.name)
                    TextField("رقم الجوال", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } footer: {
                    Text("تُنشأ بطاقة العميل في المحفظة تلقائياً بعد التسجيل.")
                }
                if !model.isOnline {
                    Label("تسجيل عميل جديد يحتاج اتصالاً بالإنترنت.", systemImage: "wifi.slash")
                        .foregroundStyle(.orange)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            .navigationTitle("عميل جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تسجيل", action: save)
                        .fontWeight(.bold)
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                let member = try await model.createMember(name: name.trimmingCharacters(in: .whitespaces),
                                                          phone: phone.trimmingCharacters(in: .whitespaces))
                dismiss()
                onCreated(member)
            } catch let apiError as APIError {
                error = apiError == .offline ? "لا يوجد اتصال. سجّل العميل عند عودة الإنترنت." : apiError.message
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct AddVehicleView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let memberId: Int

    @State private var letters = ""
    @State private var number = ""
    @State private var make = ""
    @State private var carModel = ""
    @State private var color = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("اللوحة") {
                    TextField("الحروف بالعربي (مثال: أ ب ج)", text: $letters)
                    TextField("الأرقام", text: $number).keyboardType(.numberPad)
                }
                Section("تفاصيل (اختياري)") {
                    TextField("الشركة", text: $make)
                    TextField("الموديل", text: $carModel)
                    TextField("اللون", text: $color)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            .navigationTitle("إضافة سيارة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ", action: save)
                        .fontWeight(.bold)
                        .disabled(isSaving || letters.isEmpty || number.isEmpty)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await model.createVehicle(memberId: memberId, lettersAr: letters, number: number, make: make, model: carModel, color: color)
                dismiss()
            } catch let apiError as APIError {
                error = apiError == .offline ? "إضافة سيارة تحتاج اتصالاً بالإنترنت." : apiError.message
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
