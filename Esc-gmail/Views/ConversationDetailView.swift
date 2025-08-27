import SwiftUI

struct ConversationDetailView: View {
    let thread: EmailThread
    @EnvironmentObject var conversationManager: ConversationManager
    @StateObject private var contactsManager = ContactsManager.shared
    @State private var messages: [EmailMessage] = []
    @State private var messageText = ""
    @State private var attachments: [AttachmentItem] = []
    @State private var isKeyboardVisible = false
    @State private var navigationTitle = ""
    @State private var showingAttachmentPicker = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(messages) { message in
                            MessageBubble(message: message, thread: thread)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo(messages.last?.id, anchor: .bottom)
                }
            }
            
            Divider()
            
            MessageInputView(
                text: $messageText,
                attachments: $attachments,
                onSend: {
                    Task {
                        await sendMessage()
                    }
                },
                onAttachmentAdd: {
                    showingAttachmentPicker = true
                }
            )
            .focused($isTextFieldFocused)
        }
        .navigationTitle(navigationTitle.isEmpty ? getNavigationTitle() : navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {}) {
                    Image(systemName: "info.circle")
                }
            }
        }
        .onAppear {
            loadMessages()
            loadNavigationTitle()
        }
        .onReceive(conversationManager.$threads) { updatedThreads in
            // Update messages if the thread has been updated
            if let updatedThread = updatedThreads.first(where: { $0.id == thread.id }) {
                messages = updatedThread.messages.sorted { $0.date < $1.date }
            }
        }
        .task {
            await markMessagesAsRead()
        }
        .sheet(isPresented: $showingAttachmentPicker) {
            AttachmentPickerView(
                isPresented: $showingAttachmentPicker,
                attachments: $attachments
            )
        }
    }
    
    private func loadMessages() {
        // Load messages from the thread or from the manager
        if let currentThread = conversationManager.threads.first(where: { $0.id == thread.id }) {
            messages = currentThread.messages.sorted { $0.date < $1.date }
        } else {
            messages = thread.messages.sorted { $0.date < $1.date }
        }
    }
    
    private func loadNavigationTitle() {
        if thread.isGroupConversation {
            navigationTitle = thread.getParticipantsWithContacts()
        } else {
            navigationTitle = getNavigationTitle()
        }
    }
    
    private func getNavigationTitle() -> String {
        // For group conversations, get names from address book
        if thread.isGroupConversation {
            return thread.getParticipantsWithContacts()
        }
        
        // For individual conversations, try to get contact name for the primary participant
        let userEmail = AuthenticationManager.shared.userEmail?.lowercased() ?? ""
        
        for message in thread.messages {
            if message.isFromMe {
                // Extract recipient email
                if let email = extractEmailFromString(message.to),
                   email.lowercased() != userEmail,
                   let contactName = contactsManager.getContactName(for: email) {
                    return contactName
                }
            } else {
                // Use sender email
                if message.fromEmail.lowercased() != userEmail,
                   let contactName = contactsManager.getContactName(for: message.fromEmail) {
                    return contactName
                }
            }
        }
        
        // Fallback to thread participants
        return thread.participants
    }
    
    private func extractEmailFromString(_ string: String) -> String? {
        if let startIndex = string.firstIndex(of: "<"),
           let endIndex = string.firstIndex(of: ">") {
            let range = string.index(after: startIndex)..<endIndex
            return String(string[range])
        }
        return string.contains("@") ? string.trimmingCharacters(in: .whitespaces) : nil
    }
    
    @MainActor
    private func markMessagesAsRead() async {
        for message in messages where !message.isRead {
            Task {
                try? await GmailAPIService.shared.markAsRead(messageId: message.id)
            }
        }
    }
    
    @MainActor
    private func sendMessage() async {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return }
        
        let text = messageText
        let messageAttachments = attachments
        messageText = ""
        attachments = []
        
        // Determine recipients and subject
        guard let lastMessage = messages.last else { return }
        
        var recipients: String
        var ccRecipients: String? = nil
        
        if thread.isGroupConversation {
            // For group conversations, reply to all participants
            var toAddresses = Set<String>()
            var ccAddresses = Set<String>()
            let userEmail = AuthenticationManager.shared.userEmail?.lowercased() ?? ""
            
            // Collect all unique participants from the entire thread
            for message in messages {
                // Add sender if not the user
                if !message.isFromMe && !message.fromEmail.isEmpty {
                    let email = message.fromEmail.lowercased()
                    if email != userEmail {
                        // Use the full address string to preserve names
                        let fullAddress = message.from.contains("<") ? message.from : "\(message.from) <\(message.fromEmail)>"
                        toAddresses.insert(fullAddress)
                    }
                }
                
                // Parse To recipients
                let toRecipientsList = message.to.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                for recipient in toRecipientsList {
                    let email = extractEmailFromString(recipient)?.lowercased() ?? ""
                    if email != userEmail && email.contains("@") {
                        toAddresses.insert(recipient)
                    }
                }
                
                // Parse CC recipients separately
                if let cc = message.cc, !cc.isEmpty {
                    let ccRecipientsList = cc.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                    for ccRecipient in ccRecipientsList {
                        let email = extractEmailFromString(ccRecipient)?.lowercased() ?? ""
                        if email != userEmail && email.contains("@") {
                            // Keep CC recipients in CC field for replies
                            ccAddresses.insert(ccRecipient)
                        }
                    }
                }
            }
            
            // Remove CC recipients from TO if they're already in CC
            for ccAddr in ccAddresses {
                if let ccEmail = extractEmailFromString(ccAddr)?.lowercased() {
                    toAddresses = toAddresses.filter { addr in
                        extractEmailFromString(addr)?.lowercased() != ccEmail
                    }
                }
            }
            
            recipients = Array(toAddresses).joined(separator: ", ")
            if !ccAddresses.isEmpty {
                ccRecipients = Array(ccAddresses).joined(separator: ", ")
            }
        } else {
            // For individual conversations, reply to the single participant
            recipients = lastMessage.isFromMe ? lastMessage.to : "\(lastMessage.from) <\(lastMessage.fromEmail)>"
        }
        
        let subject = lastMessage.subject.hasPrefix("Re:") ? lastMessage.subject : "Re: \(lastMessage.subject)"
        
        // Send message using the shared manager - the thread ID will be maintained by the manager
        _ = await conversationManager.sendMessage(
            to: recipients,
            cc: ccRecipients,
            subject: subject,
            body: text,
            attachments: messageAttachments,
            inReplyTo: thread.id
        )
    }
}

struct MessageBubble: View {
    let message: EmailMessage
    let thread: EmailThread
    @StateObject private var contactsManager = ContactsManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            // Show attachments above the message bubble
            if !message.attachments.isEmpty {
                HStack {
                    if message.isFromMe {
                        Spacer(minLength: 60)
                    }
                    
                    MessageAttachmentsView(
                        attachments: message.attachments,
                        isFromMe: message.isFromMe,
                        messageId: message.id
                    )
                    
                    if !message.isFromMe {
                        Spacer(minLength: 60)
                    }
                }
            }
            
            // Only show message bubble if there's actual text content
            if !cleanMessageBody(message.body).isEmpty {
                HStack(alignment: .bottom, spacing: 8) {
                if message.isFromMe {
                    Spacer(minLength: 60)
                } else {
                    // Show group icon for group conversations, contact photo for individual
                    if thread.isGroupConversation {
                        Circle()
                            .fill(backgroundColorForGroup(thread.id))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white)
                            )
                    } else if let contactImage = contactsManager.getContactImage(for: message.fromEmail) {
                        contactImage
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(backgroundColorForEmail(message.fromEmail))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Text(contactsManager.getContactInitials(for: message.fromEmail))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            )
                    }
                }
                
                VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
                    if !message.isFromMe {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contactsManager.getContactName(for: message.fromEmail) ?? message.from)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Show CC recipients if present
                            if let cc = message.cc, !cc.isEmpty, thread.isGroupConversation {
                                Text("CC: \(formatRecipients(cc))")
                                    .font(.caption2)
                                    .foregroundColor(Color.secondary.opacity(0.7))
                            }
                        }
                    }
                    
                    Text(cleanMessageBody(message.body))
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(message.isFromMe ? Color.blue : Color(.systemGray5))
                        )
                        .foregroundColor(message.isFromMe ? .white : .primary)
                    
                    Text(formatTime(message.date))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            
            if !message.isFromMe {
                Spacer(minLength: 60)
            }
            }
            } else if !message.attachments.isEmpty {
                // If there's no text but there are attachments, still show timestamp
                HStack {
                    if message.isFromMe {
                        Spacer()
                    }
                    
                    Text(formatTime(message.date))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, message.isFromMe ? 12 : 68)
                    
                    if !message.isFromMe {
                        Spacer()
                    }
                }
            }
        }
    }
    
    private func backgroundColorForEmail(_ email: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .teal, .indigo]
        let hash = email.hashValue
        let index = abs(hash) % colors.count
        return colors[index]
    }
    
    private func backgroundColorForGroup(_ groupId: String) -> Color {
        // Generate a consistent color for group conversations
        let groupColors: [Color] = [
            .blue.opacity(0.8),
            .green.opacity(0.8),
            .orange.opacity(0.8),
            .purple.opacity(0.8),
            .pink.opacity(0.8),
            .red.opacity(0.8),
            .teal.opacity(0.8),
            .indigo.opacity(0.8)
        ]
        let hash = groupId.hashValue
        let index = abs(hash) % groupColors.count
        return groupColors[index]
    }
    
    private func formatRecipients(_ recipients: String) -> String {
        let recipientList = recipients.split(separator: ",").map { 
            String($0).trimmingCharacters(in: .whitespaces)
        }
        
        if recipientList.count > 2 {
            return "\(recipientList.prefix(2).joined(separator: ", ")) +\(recipientList.count - 2)"
        }
        return recipientList.joined(separator: ", ")
    }
    
    private func cleanMessageBody(_ body: String) -> String {
        var cleanedBody = body
        
        // Remove common quote indicators and everything after them
        let quotePatterns = [
            #"On .+? wrote:[\s\S]*"#,  // Gmail style quotes
            #"On .+?, .+? at .+?, .+? <.+?> wrote:[\s\S]*"#,  // Full Gmail quote header
            #"\n>.*"#,  // Lines starting with >
            #"_{3,}[\s\S]*"#,  // Lines with 3+ underscores and everything after
            #"-{3,} ?Original Message ?-{3,}[\s\S]*"#,  // Outlook style
            #"From: .+?\nSent: .+?\nTo: .+?\nSubject: .+?[\s\S]*"#,  // Forward headers
            #"---------- Forwarded message ---------[\s\S]*"#,  // Gmail forward
            #"\*From:\*.+?\n\*Sent:\*.+?\n[\s\S]*"#,  // Bold forward headers
            #"<blockquote.+?</blockquote>"#,  // HTML blockquotes
            #"<div class=\"gmail_quote\".+?</div>"#,  // Gmail quote divs
        ]
        
        for pattern in quotePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: cleanedBody.utf16.count)
                cleanedBody = regex.stringByReplacingMatches(in: cleanedBody, options: [], range: range, withTemplate: "")
            }
        }
        
        // Remove HTML tags if present
        cleanedBody = cleanedBody.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        
        // Remove multiple newlines
        cleanedBody = cleanedBody.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        
        // Remove email signatures (lines after common signature markers)
        let signatureMarkers = ["--", "Best regards", "Sincerely", "Thanks", "Sent from my iPhone", "Sent from my iPad"]
        for marker in signatureMarkers {
            if let range = cleanedBody.range(of: "\n\(marker)", options: .caseInsensitive) {
                cleanedBody = String(cleanedBody[..<range.lowerBound])
            }
        }
        
        return cleanedBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        if Calendar.current.isDateInToday(date) {
            formatter.timeStyle = .short
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        
        return formatter.string(from: date)
    }
}


