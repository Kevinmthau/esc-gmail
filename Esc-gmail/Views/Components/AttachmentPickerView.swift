import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AttachmentPickerView: View {
    @Binding var isPresented: Bool
    @Binding var attachments: [AttachmentItem]
    
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingDocumentPicker = false
    @State private var showingPhotoPicker = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    // Photo Library Section
                    Section {
                        Button(action: {
                            showingPhotoPicker = true
                        }) {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 24))
                                    .foregroundColor(.blue)
                                    .frame(width: 40)
                                
                                Text("Photo Library")
                                    .font(.system(size: 17))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(.systemGray3))
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Files Section
                    Section {
                        Button(action: {
                            showingDocumentPicker = true
                        }) {
                            HStack {
                                Image(systemName: "folder")
                                    .font(.system(size: 24))
                                    .foregroundColor(.blue)
                                    .frame(width: 40)
                                
                                Text("Files")
                                    .font(.system(size: 17))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(.systemGray3))
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Current Attachments Section
                    if !attachments.isEmpty {
                        Section(header: Text("Current Attachments (\(attachments.count))")) {
                            ForEach(attachments) { attachment in
                                HStack {
                                    if let thumbnail = attachment.thumbnailImage {
                                        Image(uiImage: thumbnail)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 40, height: 40)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        Image(systemName: attachment.fileIcon)
                                            .font(.system(size: 20))
                                            .foregroundColor(.blue)
                                            .frame(width: 40, height: 40)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(attachment.fileName)
                                            .font(.system(size: 15))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        
                                        Text(attachment.formattedFileSize)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        withAnimation {
                                            attachments.removeAll { $0.id == attachment.id }
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(Color(.systemGray3))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                
                // Size warning
                let totalSize = attachments.reduce(0) { $0 + $1.fileSize }
                if totalSize > 20 * 1024 * 1024 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Approaching 25 MB attachment limit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                }
            }
            .navigationTitle("Add Attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: selectedPhotos) { _, newItems in
            Task {
                for item in newItems {
                    // Try to load as image data
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        guard data.count <= 25 * 1024 * 1024 else { continue }
                        
                        let fileName = item.itemIdentifier ?? "image.jpg"
                        let mimeType = AttachmentItem.mimeType(for: data)
                        let thumbnail = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 120, height: 120))
                        
                        let attachment = AttachmentItem(
                            fileName: fileName.isEmpty ? "image.jpg" : fileName,
                            mimeType: mimeType,
                            data: data,
                            thumbnailImage: thumbnail,
                            fileSize: data.count
                        )
                        
                        attachments.append(attachment)
                    }
                }
                selectedPhotos = []
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(attachments: $attachments)
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var attachments: [AttachmentItem]
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // Update delegate in case it was lost
        uiViewController.delegate = context.coordinator
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(attachments: $attachments)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        @Binding var attachments: [AttachmentItem]
        
        init(attachments: Binding<[AttachmentItem]>) {
            self._attachments = attachments
            super.init()
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            print("Document picker did pick \(urls.count) documents")
            
            for url in urls {
                print("Processing URL: \(url)")
                
                // Start accessing the security-scoped resource
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                do {
                    // Read the file data
                    let data = try Data(contentsOf: url)
                    let fileName = url.lastPathComponent
                    
                    guard data.count <= 25 * 1024 * 1024 else {
                        print("File too large: \(fileName) (\(data.count) bytes)")
                        continue
                    }
                    
                    let mimeType = AttachmentItem.mimeType(for: url)
                    
                    print("Successfully loaded file: \(fileName), size: \(data.count), mimeType: \(mimeType)")
                    
                    // Generate thumbnail for images
                    var thumbnail: UIImage? = nil
                    if mimeType.hasPrefix("image/") {
                        thumbnail = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 120, height: 120))
                    }
                    
                    let attachment = AttachmentItem(
                        fileName: fileName,
                        mimeType: mimeType,
                        data: data,
                        thumbnailImage: thumbnail,
                        fileSize: data.count
                    )
                    
                    self.attachments.append(attachment)
                    print("Added attachment. Total attachments: \(self.attachments.count)")
                    
                } catch {
                    print("Failed to load file from \(url): \(error.localizedDescription)")
                }
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("Document picker was cancelled")
        }
    }
}