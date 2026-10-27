import SwiftUI

/// A notification from another app, dropped down from the notch. Messages notifications can be answered in place.
struct NotificationCard: View {
    @ObservedObject var state: NotchState
    let note: AppNotification
    let replying: Bool

    @State private var reply = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    private var s: CGFloat { state.scale }
    private var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: note.bundleID) }
    private var appName: String {
        appURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? note.bundleID
    }
    private var isMessages: Bool { note.bundleID == MessagesReplier.bundleID }

    var body: some View {
        let size = state.closedSize
        VStack(alignment: .leading, spacing: 4 * s) {
            HStack(spacing: 0) {
                if let appURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                        .resizable()
                        .frame(width: 20 * s, height: 20 * s)
                }
                Spacer(minLength: state.notchSize.width + 12)
                Text(note.date, format: .dateTime.hour().minute())
                    .font(.system(size: 11 * s).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(height: state.notchSize.height)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(note.title.isEmpty ? appName : note.title)
                        .font(.system(size: 13 * s, weight: .semibold))
                        .lineLimit(1)
                    if !note.subtitle.isEmpty {
                        Text(note.subtitle)
                            .font(.system(size: 11 * s))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                Text(note.body)
                    .font(.system(size: 12 * s))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(replying ? 1 : 2)
            }
            .contentShape(Rectangle())
            .onTapGesture { openApp() }

            if isMessages {
                if replying {
                    replyField
                } else {
                    Button(tr("ตอบกลับ", "Reply")) { startReply() }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
        .padding(.horizontal, 22 * s)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .foregroundStyle(.white)
    }

    private var replyField: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                TextField(tr("ตอบกลับ \(note.title)…", "Reply to \(note.title)…"), text: $reply)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12 * s))
                    .focused($fieldFocused)
                    .onSubmit(send)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                Button(action: send) {
                    Image(systemName: sending ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.system(size: 20 * s))
                        .foregroundStyle(reply.isEmpty ? Color.white.opacity(0.3) : Color.blue)
                }
                .buttonStyle(.plain)
                .disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                Button { state.dismissAlert() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16 * s))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            if let error {
                Text(error).font(.system(size: 10 * s)).foregroundStyle(.red).lineLimit(1)
            }
        }
        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
    }

    private func startReply() {
        state.showAlert(.notification(note, replying: true))
        state.holdAlert(true)
        state.requestKeyboard?()
    }

    private func send() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        error = nil
        MessagesReplier.replyToLatest(text) { failure in
            sending = false
            if let failure {
                error = failure
            } else {
                state.dismissAlert()
                state.showAlert(.info(symbol: "paperplane.fill", title: tr("ส่งแล้ว", "Sent"), subtitle: text), seconds: 2)
            }
        }
    }

    private func openApp() {
        if let appURL {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
        state.dismissAlert()
    }
}
