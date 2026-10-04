import SwiftUI
import PhotosUI
import AVFoundation
import ImageIO

struct ImagePicker: UIViewControllerRepresentable {
    /// Called with the picked image and when it was taken: now for the camera,
    /// the photo's own metadata for the library (nil if it has none).
    var onPick: (UIImage, Date?) -> Void
    @Environment(\.dismiss) private var dismiss
    var sourceType: UIImagePickerController.SourceType = .camera

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                let captureDate: Date?
                if picker.sourceType == .camera {
                    captureDate = Date()
                } else {
                    captureDate = (info[.imageURL] as? URL).flatMap(Self.originalCaptureDate(ofImageAt:))
                }
                parent.onPick(image, captureDate)
            }
            parent.dismiss()
        }

        /// Reads the EXIF capture time, which is local time with no zone.
        static func originalCaptureDate(ofImageAt url: URL) -> Date? {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
                  let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            return formatter.date(from: dateString)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct PhotosPicker: View {
    @Binding var capturedPhotos: [CapturedPhoto]
    @State private var showingImagePicker = false
    @State private var showingSourceSelection = false
    @State private var useCamera = true
    @State private var showingCameraPermissionAlert = false

    var body: some View {
        Button {
            showingSourceSelection = true
        } label: {
            Label("Add Photo", systemImage: "camera.fill")
        }
        .confirmationDialog("Choose Photo Source", isPresented: $showingSourceSelection) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Camera") {
                    checkCameraPermission()
                }
            }
            Button("Photo Library") {
                useCamera = false
                showingImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Camera Access Required", isPresented: $showingCameraPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Camera access is needed to take photos. Please enable it in Settings.")
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(
                onPick: { image, captureDate in addPhoto(image, captureDate: captureDate) },
                sourceType: useCamera ? .camera : .photoLibrary
            )
        }
    }

    private func addPhoto(_ image: UIImage, captureDate: Date?) {
        let keepFullSize = UserDefaults.standard.bool(forKey: PhotoEncoder.keepFullSizeKey)
        Task {
            // Resizing and JPEG-encoding a full-resolution photo takes long
            // enough to stutter the picker's dismissal if done on the main thread
            let data = await Task.detached(priority: .userInitiated) {
                PhotoEncoder.jpegData(from: image, keepFullSize: keepFullSize)
            }.value
            if let data {
                capturedPhotos.append(CapturedPhoto(data: data, captureDate: captureDate))
            }
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            useCamera = true
            showingImagePicker = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        useCamera = true
                        showingImagePicker = true
                    } else {
                        showingCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showingCameraPermissionAlert = true
        @unknown default:
            showingCameraPermissionAlert = true
        }
    }
}
