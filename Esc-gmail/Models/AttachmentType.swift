import Foundation

enum AttachmentType: CaseIterable {
    case image
    case video
    case pdf
    case audio
    case archive
    case document
    case spreadsheet
    case presentation
    case text
    case other
    
    init(mimeType: String) {
        switch mimeType.lowercased() {
        case let type where type.hasPrefix("image/"):
            self = .image
        case let type where type.hasPrefix("video/"):
            self = .video
        case "application/pdf":
            self = .pdf
        case let type where type.hasPrefix("audio/"):
            self = .audio
        case let type where type.contains("zip") || type.contains("archive") || type.contains("compressed"):
            self = .archive
        case let type where type.contains("word") || type.contains("document") || type.contains("msword"):
            self = .document
        case let type where type.contains("sheet") || type.contains("excel") || type.contains("spreadsheet"):
            self = .spreadsheet
        case let type where type.contains("presentation") || type.contains("powerpoint") || type.contains("slides"):
            self = .presentation
        case let type where type.contains("text") || type.hasPrefix("text/"):
            self = .text
        default:
            self = .other
        }
    }
    
    var iconName: String {
        switch self {
        case .image:
            return "photo"
        case .video:
            return "video"
        case .pdf:
            return "doc"
        case .audio:
            return "music.note"
        case .archive:
            return "doc.zipper"
        case .document:
            return "doc.text"
        case .spreadsheet:
            return "tablecells"
        case .presentation:
            return "play.rectangle"
        case .text:
            return "doc.text"
        case .other:
            return "paperclip"
        }
    }
    
    var isPreviewable: Bool {
        switch self {
        case .image, .video, .pdf, .audio, .text, .document, .spreadsheet, .presentation:
            return true
        case .archive, .other:
            return false
        }
    }
    
    var requiresDownload: Bool {
        switch self {
        case .image:
            return false
        default:
            return true
        }
    }
}

extension AttachmentType {
    static func detectFromData(_ data: Data) -> AttachmentType {
        let bytes = [UInt8](data.prefix(12))
        
        if bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return .image
        }
        
        if bytes.count >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return .image
        }
        
        if bytes.count >= 6 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 {
            return .image
        }
        
        if bytes.count >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 {
            return .pdf
        }
        
        return .other
    }
    
    static func mimeTypeFromData(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        
        if bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "image/jpeg"
        }
        
        if bytes.count >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        }
        
        if bytes.count >= 6 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 {
            return "image/gif"
        }
        
        if bytes.count >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 {
            return "application/pdf"
        }
        
        return "application/octet-stream"
    }
}