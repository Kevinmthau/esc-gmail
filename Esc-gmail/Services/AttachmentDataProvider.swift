import Foundation
import UIKit

@MainActor
class AttachmentDataProvider: ObservableObject {
    static let shared = AttachmentDataProvider()
    
    private let cache = NSCache<NSString, AttachmentData>()
    private let imageCache = ImageCache.shared
    
    private init() {
        cache.countLimit = 50
        cache.totalCostLimit = 100 * 1024 * 1024
    }
    
    class AttachmentData: NSObject {
        let data: Data
        let type: AttachmentType
        let thumbnailImage: UIImage?
        
        init(data: Data, type: AttachmentType, thumbnailImage: UIImage? = nil) {
            self.data = data
            self.type = type
            self.thumbnailImage = thumbnailImage
            super.init()
        }
    }
    
    func loadAttachmentData(
        for attachment: MessageAttachment,
        messageId: String
    ) async throws -> AttachmentData {
        let cacheKey = "\(messageId)_\(attachment.attachmentId ?? attachment.filename)" as NSString
        
        if let cachedData = cache.object(forKey: cacheKey) {
            return cachedData
        }
        
        guard let attachmentId = attachment.attachmentId else {
            throw AttachmentError.missingAttachmentId
        }
        
        let data = try await GmailAPIService.shared.getAttachment(
            messageId: messageId,
            attachmentId: attachmentId
        )
        
        let type = AttachmentType(mimeType: attachment.mimeType)
        var thumbnailImage: UIImage?
        
        if type == .image {
            thumbnailImage = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 120, height: 120))
            
            if let image = UIImage(data: data) {
                let imageCacheKey = "\(messageId)_\(attachmentId)"
                await imageCache.store(image, for: imageCacheKey)
            }
        } else if type == .pdf {
            thumbnailImage = generatePDFThumbnail(from: data)
        }
        
        let attachmentData = AttachmentData(
            data: data,
            type: type,
            thumbnailImage: thumbnailImage
        )
        
        cache.setObject(attachmentData, forKey: cacheKey, cost: data.count)
        
        return attachmentData
    }
    
    func preloadAttachments(
        for attachments: [MessageAttachment],
        messageId: String
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for attachment in attachments {
                group.addTask { [weak self] in
                    do {
                        _ = try await self?.loadAttachmentData(
                            for: attachment,
                            messageId: messageId
                        )
                    } catch {
                        print("Failed to preload attachment: \(error)")
                    }
                }
            }
        }
    }
    
    func getCachedImage(for messageId: String, attachmentId: String) async -> UIImage? {
        let cacheKey = "\(messageId)_\(attachmentId)"
        return await imageCache.image(for: cacheKey)
    }
    
    func saveAttachmentToFile(_ data: Data, fileName: String) -> URL? {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first
        
        guard let documentsPath = documentsPath else { return nil }
        
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to save attachment: \(error)")
            return nil
        }
    }
    
    private func generatePDFThumbnail(from data: Data) -> UIImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdfDocument = CGPDFDocument(provider),
              let pdfPage = pdfDocument.page(at: 1) else {
            return nil
        }
        
        let pageRect = pdfPage.getBoxRect(.mediaBox)
        let scale = min(120 / pageRect.width, 120 / pageRect.height)
        let scaledSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )
        
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: scaledSize))
            
            context.cgContext.translateBy(x: 0, y: scaledSize.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            context.cgContext.drawPDFPage(pdfPage)
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
}

enum AttachmentError: LocalizedError {
    case missingAttachmentId
    case loadFailed
    case unsupportedType
    
    var errorDescription: String? {
        switch self {
        case .missingAttachmentId:
            return "Attachment ID is missing"
        case .loadFailed:
            return "Failed to load attachment"
        case .unsupportedType:
            return "Unsupported attachment type"
        }
    }
}