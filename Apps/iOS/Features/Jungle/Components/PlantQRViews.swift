import SwiftUI
import SunnieShared
#if canImport(CoreImage)
import CoreImage
import CoreImage.CIFilterBuiltins
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Renders a plant's QR label (PLANT_CARE.md §11).
///
/// The code encodes an opaque token and nothing else. A printed label sits on a
/// shelf where anyone can photograph it, so it must not carry a nickname, a note,
/// or anything else private — scanning it means nothing without this app and this
/// device's data.
///
/// Generated with Core Image, which is on-device and needs no network.
struct PlantQRCodeView: View {
    @Environment(\.sunnieTheme) private var theme

    let token: String
    let plantName: String

    var body: some View {
        VStack(spacing: Space.s) {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .padding(Space.s)
                    // A white quiet zone regardless of theme: scanners need the
                    // contrast, and a cream background at night would make the
                    // code unreliable.
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.image, style: .continuous))
                    .accessibilityLabel(Text(
                        "plant.qr.accessibility \(plantName)",
                        bundle: .main,
                        comment: "Describes the QR code image"
                    ))
            } else {
                Text("plant.qr.unavailable", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            }

            // The name is printed under the code so a label is readable by a
            // person as well as a scanner — a house-sitter should not have to
            // scan five pots to find the right one.
            Text(plantName)
                .font(SunnieFont.cardTitle)
                .foregroundStyle(theme.color.textPrimary)
        }
    }

    #if canImport(CoreImage) && canImport(UIKit)
    private var image: UIImage? {
        let payload = PlantQRIdentity.payload(token: token)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        // High error correction: a label on a pot gets wet, scuffed, and
        // partially peeled, and should still scan.
        filter.correctionLevel = "H"

        guard let output = filter.outputImage else { return nil }
        // The generator emits roughly a 25pt image; scaling up with no
        // interpolation keeps the modules crisp when printed.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
    #else
    private var image: UIImage? { nil }
    #endif
}

/// Scans a plant label and hands back the plant (PLANT_CARE.md §11).
///
/// **Placeholder presentation** — a bare camera preview with a cancel button.
/// Scanning something that is not one of our labels does nothing at all, rather
/// than guessing or showing an error: pointing a camera at a barcode should not
/// produce a complaint.
struct PlantScannerSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    let onResolved: (Plant) -> Void

    @State private var message: String?
    @State private var isResolving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.m) {
                #if canImport(AVFoundation) && canImport(UIKit)
                QRScannerView { code in
                    Task { await resolve(code) }
                }
                .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))
                .padding(Space.m)
                #else
                Text("plant.scan.unavailable", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
                #endif

                Text(message ?? String(
                    localized: "plant.scan.hint",
                    defaultValue: "Point the camera at a plant label.",
                    comment: "Guidance while scanning"
                ))
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.m)

                Spacer()
            }
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("plant.scan.title", bundle: .main))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(
                        localized: "common.cancel",
                        defaultValue: "Cancel",
                        comment: "Cancel"
                    )) { dismiss() }
                }
            }
        }
    }

    private func resolve(_ code: String) async {
        // The scanner fires repeatedly while a code is in frame; without this the
        // same label would resolve dozens of times a second.
        guard !isResolving else { return }
        isResolving = true
        defer { isResolving = false }

        guard let plant = try? await dependencies.managePlant.plant(forScannedCode: code) else {
            // A code we don't recognise, or one whose plant is gone. Said once,
            // gently, and scanning continues.
            message = String(
                localized: "plant.scan.unknown",
                defaultValue: "That isn't a label from this app — or its plant isn't here any more.",
                comment: "Shown when a scanned code resolves to nothing"
            )
            return
        }

        dependencies.haptics.success()
        onResolved(plant)
        dismiss()
    }
}

#if canImport(AVFoundation) && canImport(UIKit)
/// Camera preview that reports QR payloads.
///
/// Wraps `AVCaptureSession` directly rather than pulling in a scanning library —
/// the whole job is one metadata output and one delegate callback, and a
/// third-party package would need an ADR.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: QRScannerController, context: Context) {
        controller.onCode = onCode
    }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !session.isRunning else { return }
        // Starting the session blocks; off the main thread so the sheet's
        // presentation animation is not interrupted.
        Task.detached(priority: .userInitiated) { [session] in
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // The camera must stop the moment the sheet leaves. Leaving it running
        // means a green indicator light with no visible camera on screen.
        guard session.isRunning else { return }
        Task.detached(priority: .userInitiated) { [session] in
            session.stopRunning()
        }
    }

    private func configureSession() {
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        output.setMetadataObjectsDelegate(self, queue: .main)
        // QR only. Restricting the types means a barcode on a plant pot's price
        // sticker never produces a callback at all.
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let value = object.stringValue
        else { return }
        onCode?(value)
    }
}
#endif
