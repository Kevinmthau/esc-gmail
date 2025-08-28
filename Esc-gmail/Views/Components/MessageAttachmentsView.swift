import SwiftUI

struct MessageAttachmentsView: View {
    let attachments: [MessageAttachment]
    let isFromMe: Bool
    let messageId: String
    
    var body: some View {
        VStack(alignment: isFromMe ? .trailing : .leading, spacing: 8) {
            ForEach(attachments, id: \.self) { attachment in
                AttachmentViewerFactory.viewer(
                    for: attachment,
                    messageId: messageId,
                    isFromMe: isFromMe
                )
            }
        }
    }
}

