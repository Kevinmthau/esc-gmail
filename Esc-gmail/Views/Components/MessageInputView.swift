import SwiftUI
import PhotosUI

struct MessageInputView: View {
    @Binding var text: String
    @Binding var attachments: [AttachmentItem]
    let placeholder: String
    let isEnabled: Bool
    let onSend: () -> Void
    let onAttachmentAdd: () -> Void
    
    @State private var textHeight: CGFloat = 0
    
    init(
        text: Binding<String>,
        attachments: Binding<[AttachmentItem]> = .constant([]),
        placeholder: String = "iMessage",
        isEnabled: Bool = true,
        onSend: @escaping () -> Void,
        onAttachmentAdd: @escaping () -> Void = {}
    ) {
        self._text = text
        self._attachments = attachments
        self.placeholder = placeholder
        self.isEnabled = isEnabled
        self.onSend = onSend
        self.onAttachmentAdd = onAttachmentAdd
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Attachment preview area
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            AttachmentPreviewView(attachment: attachment) {
                                removeAttachment(attachment)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemBackground))
                
                Divider()
            }
            
            // Message input area
            HStack(alignment: .bottom, spacing: 8) {
                // Attachment button
                Button(action: onAttachmentAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                }
                .disabled(!isEnabled)
                
                // Text input field
                HStack(alignment: .bottom) {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .lineLimit(1...10)
                        .disabled(!isEnabled)
                        .onSubmit {
                            if !text.isEmpty && isEnabled {
                                onSend()
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                
                // Send button
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(sendButtonColor)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }
    
    private var canSend: Bool {
        isEnabled && (!text.isEmpty || !attachments.isEmpty)
    }
    
    private var sendButtonColor: Color {
        canSend ? .blue : .gray
    }
    
    private func removeAttachment(_ attachment: AttachmentItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            attachments.removeAll { $0.id == attachment.id }
        }
    }
}

struct AttachmentPreviewView: View {
    let attachment: AttachmentItem
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Preview content
            Group {
                if let image = attachment.thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: attachment.fileIcon)
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                        
                        Text(attachment.fileName)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(width: 60, height: 60)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .offset(x: 5, y: -5)
        }
    }
}