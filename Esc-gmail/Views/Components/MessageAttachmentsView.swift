import SwiftUI

struct MessageAttachmentsView: View {
    let attachments: [MessageAttachment]
    let isFromMe: Bool
    let messageId: String
    
    var body: some View {
        VStack(alignment: isFromMe ? .trailing : .leading, spacing: 8) {
            ForEach(attachments, id: \.self) { attachment in
                if attachment.mimeType.hasPrefix("image/") {
                    ImageAttachmentView(
                        attachment: attachment,
                        messageId: messageId,
                        isFromMe: isFromMe
                    )
                } else {
                    AttachmentCard(attachment: attachment, isFromMe: isFromMe)
                }
            }
        }
    }
}

struct AttachmentCard: View {
    let attachment: MessageAttachment
    let isFromMe: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForMimeType(attachment.mimeType))
                .font(.system(size: 20))
                .foregroundColor(isFromMe ? .white.opacity(0.9) : .blue)
                .frame(width: 30, height: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isFromMe ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if let size = attachment.size {
                    Text(formatFileSize(size))
                        .font(.caption)
                        .foregroundColor(isFromMe ? .white.opacity(0.8) : .secondary)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 250)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isFromMe ? Color.blue.opacity(0.9) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFromMe ? Color.clear : Color(.systemGray4), lineWidth: 0.5)
        )
    }
    
    private func iconForMimeType(_ mimeType: String) -> String {
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
        } else if mimeType.contains("word") || mimeType.contains("document") {
            return "doc.text"
        } else if mimeType.contains("sheet") || mimeType.contains("excel") {
            return "tablecells"
        } else if mimeType.contains("presentation") || mimeType.contains("powerpoint") {
            return "play.rectangle"
        } else if mimeType.contains("text") {
            return "doc.text"
        } else {
            return "paperclip"
        }
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct ImageAttachmentView: View {
    let attachment: MessageAttachment
    let messageId: String
    let isFromMe: Bool
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadError = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 250, height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(.systemGray6), lineWidth: 0.33)
                    )
            } else if isLoading {
                // Loading placeholder
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray6))
                    .frame(width: 250, height: 200)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text(attachment.filename)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    )
            } else if loadError {
                // Error state - show as regular attachment
                AttachmentCard(attachment: attachment, isFromMe: isFromMe)
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let attachmentId = attachment.attachmentId else {
            // If no attachment ID, show as regular attachment card
            await MainActor.run {
                isLoading = false
                loadError = true
            }
            return
        }
        
        let cacheKey = "\(messageId)_\(attachmentId)"
        
        // Check cache first
        if let cachedImage = await ImageCache.shared.image(for: cacheKey) {
            await MainActor.run {
                self.image = cachedImage
                self.isLoading = false
            }
            return
        }
        
        do {
            // Fetch the attachment data from Gmail API
            let attachmentData = try await GmailAPIService.shared.getAttachment(
                messageId: messageId,
                attachmentId: attachmentId
            )
            
            if let uiImage = UIImage(data: attachmentData) {
                // Store in cache
                await ImageCache.shared.store(uiImage, for: cacheKey)
                
                await MainActor.run {
                    self.image = uiImage
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.loadError = true
                    self.isLoading = false
                }
            }
        } catch {
            print("Failed to load attachment: \(error)")
            await MainActor.run {
                self.loadError = true
                self.isLoading = false
            }
        }
    }
}