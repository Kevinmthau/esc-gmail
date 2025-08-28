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
    
    var type: AttachmentType {
        AttachmentType(mimeType: mimeType)
    }
    
    var fileIcon: String {
        type.iconName
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
        AttachmentType.mimeTypeFromData(data)
    }
}