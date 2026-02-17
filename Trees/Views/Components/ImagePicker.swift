import SwiftUI
import PhotosUI
import AVFoundation

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
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
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct PhotosPicker: View {
    @Binding var selectedPhotos: [Data]
    @Binding var photoDates: [Date?]
    @State private var showingImagePicker = false
    @State private var showingSourceSelection = false
    @State private var selectedImage: UIImage?
    @State private var useCamera = true
    @State private var showingCameraPermissionAlert = false

    var body: some View {
        Button {
            showingSourceSelection = true
        } label: {
            Label("Add Photo", systemImage: "camera.fill")
        }
        .confirmationDialog("Choose Photo Source", isPresented: $showingSourceSelection) {
            Button("Camera") {
                checkCameraPermission()
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
                image: $selectedImage,
                sourceType: useCamera ? .camera : .photoLibrary
            )
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                selectedPhotos.append(data)
                photoDates.append(Date())
                selectedImage = nil
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
