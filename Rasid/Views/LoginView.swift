import RasidKit
import SwiftUI

/// The single sign-in screen for both merchants and cashiers; the account's
/// role decides which tabs appear afterwards.
struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 84, height: 84)
                    Text("رصيد")
                        .font(.largeTitle.weight(.heavy))
                    Text("دخول التاجر والكاشير")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 56)

                VStack(spacing: 14) {
                    field(icon: "envelope.fill") {
                        TextField("البريد الإلكتروني", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                    }
                    field(icon: "lock.fill") {
                        Group {
                            if showPassword {
                                TextField("كلمة المرور", text: $password)
                            } else {
                                SecureField("كلمة المرور", text: $password)
                            }
                        }
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel(showPassword ? "إخفاء كلمة المرور" : "إظهار كلمة المرور")
                    }
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    HStack {
                        if isLoading { ProgressView().tint(.white) }
                        Text("تسجيل الدخول").fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(isLoading || email.isEmpty || password.isEmpty)

                Text("تبقى مسجلاً على هذا الجهاز حتى تختار تسجيل الخروج.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
    }

    private func field<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.brand)
                .frame(width: 22)
            content()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty, !isLoading else { return }
        focus = nil
        isLoading = true
        error = nil
        Task {
            defer { isLoading = false }
            do {
                try await model.login(email: email, password: password)
            } catch let apiError as APIError {
                error = apiError.message
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
