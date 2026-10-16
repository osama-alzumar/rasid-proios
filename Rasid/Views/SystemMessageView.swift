import RasidKit
import SwiftUI

/// A platform announcement, shown over the app like the website's modal.
struct SystemMessageView: View {
    @EnvironmentObject private var model: AppModel
    let message: SystemMessage

    private var color: Color {
        switch message.tone {
        case .success: return Theme.brand
        case .warning: return .orange
        case .danger: return .red
        case .info: return .blue
        }
    }

    private var symbol: String {
        switch message.tone {
        case .success: return "checkmark.seal.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "exclamationmark.octagon.fill"
        case .info: return "megaphone.fill"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(color.gradient, in: Circle())
                .padding(.top, 28)
            Text(message.title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            ScrollView {
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 260)
            Button {
                model.acknowledgeSystemMessage(message)
            } label: {
                Text("فهمت").fontWeight(.bold).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(color)
            if !message.isForced {
                Button("إغلاق") { model.dismissSystemMessage(message) }
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(message.isForced ? .hidden : .visible)
        .interactiveDismissDisabled(message.isForced)
    }
}
