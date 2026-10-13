import AVFoundation
import SwiftUI
import UIKit

/// Live camera scanner for the code on the customer's Wallet card
/// (QR, Code 128, PDF417 or Aztec).
struct CodeScannerView: UIViewControllerRepresentable {
    var isActive: Bool
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {
        controller.onCode = onCode
        controller.setRunning(isActive)
    }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "rasid.scanner")
    private var preview: AVCaptureVideoPreviewLayer?
    private var configured = false
    private var lastCode: String?
    private var lastCodeAt = Date.distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        sessionQueue.async { [weak self] in self?.configure() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    func setRunning(_ running: Bool) {
        sessionQueue.async { [weak self] in
            guard let self, self.configured else { return }
            if running && !self.session.isRunning { self.session.startRunning() }
            if !running && self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.beginConfiguration()
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        let wanted: [AVMetadataObject.ObjectType] = [.qr, .code128, .pdf417, .aztec, .ean13, .code39]
        output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }
        session.commitConfiguration()
        configured = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let layer = AVCaptureVideoPreviewLayer(session: self.session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = self.view.bounds
            self.view.layer.addSublayer(layer)
            self.preview = layer
        }
        session.startRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue, !code.isEmpty else { return }
        // The same card stays in frame for a while; report it once.
        if code == lastCode && Date().timeIntervalSince(lastCodeAt) < 3 { return }
        lastCode = code
        lastCodeAt = Date()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(code)
    }
}

enum CameraAccess {
    static var status: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
