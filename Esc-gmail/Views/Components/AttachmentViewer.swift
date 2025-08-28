import SwiftUI
import QuickLook

protocol AttachmentViewerProtocol {
    associatedtype Content: View
    func makeView(for attachment: MessageAttachment, messageId: String, isFromMe: Bool) -> Content
}

struct AttachmentViewerFactory {
    @MainActor
    static func viewer(for attachment: MessageAttachment, messageId: String, isFromMe: Bool) -> AnyView {
        switch attachment.type {
        case .image:
            return AnyView(
                ImageAttachmentViewer(
                    attachment: attachment,
                    messageId: messageId,
                    isFromMe: isFromMe
                )
            )
        default:
            return AnyView(
                GenericAttachmentViewer(
                    attachment: attachment,
                    messageId: messageId,
                    isFromMe: isFromMe
                )
            )
        }
    }
}

struct ImageAttachmentViewer: View, AttachmentViewerProtocol {
    let attachment: MessageAttachment
    let messageId: String
    let isFromMe: Bool
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadError = false
    @State private var fileURL: URL?
    @StateObject private var dataProvider = AttachmentDataProvider.shared
    
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            await prepareAndShowNativeViewer()
                        }
                    }
            } else if isLoading {
                LoadingAttachmentView(attachment: attachment)
            } else if loadError {
                ErrorAttachmentView(attachment: attachment, isFromMe: isFromMe)
            }
        }
        .task {
            await loadImage()
        }
        .quickLookPreview($fileURL)
    }
    
    func makeView(for attachment: MessageAttachment, messageId: String, isFromMe: Bool) -> some View {
        ImageAttachmentViewer(attachment: attachment, messageId: messageId, isFromMe: isFromMe)
    }
    
    private func prepareAndShowNativeViewer() async {
        // If we already have the file URL, just trigger QuickLook
        if fileURL != nil {
            return
        }
        
        // Otherwise, save the image and show it
        do {
            let attachmentData = try await dataProvider.loadAttachmentData(
                for: attachment,
                messageId: messageId
            )
            
            if let url = dataProvider.saveAttachmentToFile(
                attachmentData.data,
                fileName: attachment.filename
            ) {
                await MainActor.run {
                    self.fileURL = url  // This triggers QuickLook
                }
            }
        } catch {
            print("Failed to prepare image for viewing: \(error)")
        }
    }
    
    private func loadImage() async {
        guard let attachmentId = attachment.attachmentId else {
            await MainActor.run {
                isLoading = false
                loadError = true
            }
            return
        }
        
        if let cachedImage = await dataProvider.getCachedImage(for: messageId, attachmentId: attachmentId) {
            await MainActor.run {
                self.image = cachedImage
                self.isLoading = false
            }
            return
        }
        
        do {
            let attachmentData = try await dataProvider.loadAttachmentData(
                for: attachment,
                messageId: messageId
            )
            
            if let uiImage = UIImage(data: attachmentData.data) {
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

struct GenericAttachmentViewer: View, AttachmentViewerProtocol {
    let attachment: MessageAttachment
    let messageId: String
    let isFromMe: Bool
    
    @State private var showingViewer = false
    @State private var isLoadingData = false
    @State private var fileURL: URL?
    @StateObject private var dataProvider = AttachmentDataProvider.shared
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: attachment.fileIcon)
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
            
            if isLoadingData {
                ProgressView()
                    .scaleEffect(0.8)
                    .progressViewStyle(CircularProgressViewStyle(tint: isFromMe ? .white : .blue))
            }
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
        .contentShape(Rectangle())
        .onTapGesture {
            if attachment.isPreviewable {
                Task {
                    await loadAndShowAttachment()
                }
            }
        }
        .quickLookPreview($fileURL)
    }
    
    func makeView(for attachment: MessageAttachment, messageId: String, isFromMe: Bool) -> some View {
        GenericAttachmentViewer(attachment: attachment, messageId: messageId, isFromMe: isFromMe)
    }
    
    private func loadAndShowAttachment() async {
        guard fileURL == nil else {
            // File already loaded, just trigger the preview
            return
        }
        
        await MainActor.run {
            isLoadingData = true
        }
        
        do {
            let attachmentData = try await dataProvider.loadAttachmentData(
                for: attachment,
                messageId: messageId
            )
            
            if let url = dataProvider.saveAttachmentToFile(
                attachmentData.data,
                fileName: attachment.filename
            ) {
                await MainActor.run {
                    self.fileURL = url  // This triggers QuickLook via the binding
                    self.isLoadingData = false
                }
            }
        } catch {
            print("Failed to load attachment: \(error)")
            await MainActor.run {
                isLoadingData = false
            }
        }
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct LoadingAttachmentView: View {
    let attachment: MessageAttachment
    
    var body: some View {
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
    }
}

struct ErrorAttachmentView: View {
    let attachment: MessageAttachment
    let isFromMe: Bool
    
    var body: some View {
        GenericAttachmentViewer(
            attachment: attachment,
            messageId: "",
            isFromMe: isFromMe
        )
    }
}

