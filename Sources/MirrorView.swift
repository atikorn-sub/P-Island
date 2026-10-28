import AVFoundation
import SwiftUI

/// The front camera as a mirror, for a quick look before a call. The camera runs only while this tab
/// is showing, and nothing is recorded or saved.
struct MirrorView: View {
    @StateObject private var camera = MirrorCamera()

    var body: some View {
        Group {
            switch camera.state {
            case .running:
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            case .starting:
                ProgressView().controlSize(.small)
            case .denied:
                message(tr("P Island ยังไม่ได้รับอนุญาตให้ใช้กล้อง", "P Island isn't allowed to use the camera"),
                        button: tr("เปิดการตั้งค่ากล้อง", "Open Camera Settings")) { MirrorCamera.openSettings() }
            case .noCamera:
                message(tr("ไม่พบกล้อง", "No camera found"), button: nil) {}
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private func message(_ text: String, button: String?, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "web.camera")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.35))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            if let button {
                Button(button, action: action).buttonStyle(PillButtonStyle())
            }
        }
    }
}

final class MirrorCamera: ObservableObject {
    enum State { case starting, running, denied, noCamera }

    @Published private(set) var state: State = .starting
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "islet.mirror")
    private var configured = false
    private var wanted = false

    func start() {
        wanted = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.run() } else { self.state = .denied }
                }
            }
        default:
            state = .denied
        }
    }

    func stop() {
        wanted = false
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func run() {
        guard wanted else { return }
        queue.async {
            if !self.configured {
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    DispatchQueue.main.async { self.state = .noCamera }
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                self.session.addInput(input)
                self.session.commitConfiguration()
                self.configured = true
            }
            // The tab may have closed while the camera was being set up.
            guard self.wanted else { return }
            self.session.startRunning()
            DispatchQueue.main.async { self.state = .running }
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The live picture, flipped like a mirror and filling its frame.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
