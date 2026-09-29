import SwiftUI
import UIKit

/// The system camera for photographing a result sheet. A plain photo, not the
/// document scanner: flattening and enhancing a receipt-style printout blurred
/// its digits in testing, while the photo as taken read cleanly.
struct InBodyCameraPicker: UIViewControllerRepresentable {
    /// False on the simulator and on devices without a camera.
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onCapture(image) } else { onCancel() }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
    }
}

extension UIImage {
    /// Upright JPEG no larger than `maxPixelSize` on its long edge, for the
    /// sheet reader. The camera's orientation is applied by drawing.
    func uprightJPEGData(maxPixelSize: CGFloat = CGFloat(InBodySheetRecognizer.passSizes[0])) -> Data? {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        let factor = min(1, maxPixelSize / max(pixels.width, pixels.height, 1))
        let target = CGSize(width: (pixels.width * factor).rounded(), height: (pixels.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).jpegData(withCompressionQuality: 0.95) { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
