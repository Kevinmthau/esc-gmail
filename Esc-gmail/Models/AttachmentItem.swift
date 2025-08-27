import Foundation
import UIKit
import UniformTypeIdentifiers

struct AttachmentItem: Identifiable {
    let id = UUID()
    let fileName: String
    let mimeType: String
    let data: Data
    let thumbnailImage: UIImage?
    let fileSize: Int
    
    var fileIcon: String {
        if mimeType.hasPrefix("image/") {
            return "photo"
        } else if mimeType.hasPrefix("video/") {
            return "video"
        } else if mimeType == "application/pdf" {
            return "doc"
        } else if mimeType.hasPrefix("audio/") {
            return "music.note"
        } else if mimeType.contains("zip") || mimeType.contains("archive") {
            return "doc.zipper"
        } else if mimeType.contains("text") {
            return "doc.text"
        } else {
            return "doc"
        }
    }
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }
    
    static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
    
    static func mimeType(for data: Data) -> String {
        // Check for common image formats
        let bytes = [UInt8](data.prefix(12))
        
        // JPEG
        if bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "image/jpeg"
        }
        
        // PNG
        if bytes.count >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        }
        
        // GIF
        if bytes.count >= 6 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 {
            return "image/gif"
        }
        
        // PDF
        if bytes.count >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 {
            return "application/pdf"
        }
        
        // Default
        return "application/octet-stream"
    }
}