import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class AttachmentManager: NSObject, ObservableObject {
    static let shared = AttachmentManager()
    
    @Published var attachments: [AttachmentItem] = []
    @Published var isLoadingAttachment = false
    @Published var errorMessage: String?
    
    // Maximum file size: 25 MB (Gmail's limit)
    private let maxFileSize = 25 * 1024 * 1024
    
    override private init() {
        super.init()
    }
    
    // MARK: - Photo Selection
    
    func loadPhoto(from item: PhotosPickerItem) async {
        isLoadingAttachment = true
        errorMessage = nil
        
        do {
            // Try to load as image first
            if let data = try await item.loadTransferable(type: Data.self) {
                await processImageData(data, fileName: item.itemIdentifier ?? "image.jpg")
            }
        } catch {
            errorMessage = "Failed to load photo: \(error.localizedDescription)"
        }
        
        isLoadingAttachment = false
    }
    
    func loadPhotos(from items: [PhotosPickerItem]) async {
        for item in items {
            await loadPhoto(from: item)
        }
    }
    
    private func processImageData(_ data: Data, fileName: String) async {
        guard data.count <= maxFileSize else {
            // Try to compress if too large
            if let compressed = await compressImage(data) {
                await processImageData(compressed, fileName: fileName)
            } else {
                errorMessage = "Image is too large (max 25 MB)"
            }
            return
        }
        
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
    
    private func compressImage(_ data: Data) async -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        
        // Try different compression levels
        let compressionLevels: [CGFloat] = [0.8, 0.6, 0.4, 0.2]
        
        for level in compressionLevels {
            if let compressed = image.jpegData(compressionQuality: level),
               compressed.count <= maxFileSize {
                return compressed
            }
        }
        
        // If still too large, resize the image
        let maxDimension: CGFloat = 2048
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
        
        if scale < 1.0 {
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            
            return await withCheckedContinuation { continuation in
                UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                image.draw(in: CGRect(origin: .zero, size: newSize))
                let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                
                let compressed = resizedImage?.jpegData(compressionQuality: 0.8)
                continuation.resume(returning: compressed)
            }
        }
        
        return nil
    }
    
    // MARK: - File Selection
    
    func loadFile(from url: URL) async {
        isLoadingAttachment = true
        errorMessage = nil
        
        do {
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Cannot access file"
                isLoadingAttachment = false
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            let data = try Data(contentsOf: url)
            
            guard data.count <= maxFileSize else {
                errorMessage = "File is too large (max 25 MB)"
                isLoadingAttachment = false
                return
            }
            
            let fileName = url.lastPathComponent
            let mimeType = AttachmentItem.mimeType(for: url)
            
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
            
            attachments.append(attachment)
            
        } catch {
            errorMessage = "Failed to load file: \(error.localizedDescription)"
        }
        
        isLoadingAttachment = false
    }
    
    // MARK: - Attachment Management
    
    func removeAttachment(_ attachment: AttachmentItem) {
        attachments.removeAll { $0.id == attachment.id }
    }
    
    func removeAllAttachments() {
        attachments.removeAll()
    }
    
    func totalAttachmentSize() -> Int {
        attachments.reduce(0) { $0 + $1.fileSize }
    }
    
    func canAddMoreAttachments() -> Bool {
        // Gmail typically allows up to 25MB total
        return totalAttachmentSize() < maxFileSize
    }
}

// MARK: - UIDocumentPickerDelegate

extension AttachmentManager: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Task {
            for url in urls {
                await loadFile(from: url)
            }
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // Handle cancellation if needed
    }
}