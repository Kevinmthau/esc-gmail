import Foundation
import SwiftUI

@MainActor
class ConversationManager: ObservableObject {
    static let shared = ConversationManager()
    
    @Published var threads: [EmailThread] = []
    @Published var isLoading = false
    @Published var loadingProgress: String = ""
    @Published var syncProgress: Double = 0.0
    
    private let gmailService = GmailAPIService.shared
    private var allThreadsCache: [String: EmailThread] = [:]
    private var lastSyncDate: Date?
    
    private init() {}
    
    // Generate a consistent thread ID based on participant emails
    private func generateThreadId(from participants: Set<String>, isGroup: Bool) -> String {
        guard !participants.isEmpty else { return UUID().uuidString }
        
        if !isGroup && participants.count == 1 {
            // For individual conversations, use the participant's email
            return participants.first ?? UUID().uuidString
        } else {
            // For group conversations, create a consistent ID from sorted participants
            let sortedParticipants = participants.sorted().joined(separator: "|")
            return "group-\(sortedParticipants.hashValue)"
        }
    }
    
    // Extract all participants from a set of messages (excluding the current user)
    private func extractParticipants(from messages: [EmailMessage]) -> Set<String> {
        var participants = Set<String>()
        let userEmail = AuthenticationManager.shared.userEmail?.lowercased() ?? ""
        
        for message in messages {
            // Add sender if not the user
            if !message.isFromMe {
                let senderEmail = message.fromEmail.lowercased()
                if !senderEmail.isEmpty && senderEmail != userEmail {
                    participants.insert(senderEmail)
                }
            }
            
            // Add all recipients (To, CC)
            for recipient in message.allRecipients {
                let email = extractEmail(from: recipient).lowercased()
                if !email.isEmpty && email != userEmail && email.contains("@") {
                    participants.insert(email)
                }
            }
        }
        
        return participants
    }
    
    func loadMessages() async {
        isLoading = true
        loadingProgress = "Starting sync..."
        syncProgress = 0.0
        
        // Request contacts access if needed
        if ContactsManager.shared.authorizationStatus == .notDetermined {
            _ = await ContactsManager.shared.requestAccess()
        }
        
        do {
            // Fetch all threads efficiently
            loadingProgress = "Fetching all threads..."
            let allThreadIds = try await fetchAllThreadIds()
            
            if allThreadIds.isEmpty {
                loadingProgress = "No messages found"
                isLoading = false
                return
            }
            
            loadingProgress = "Loading \(allThreadIds.count) conversations..."
            await loadThreadsInBatches(threadIds: allThreadIds)
            
            loadingProgress = ""
            syncProgress = 1.0
            
        } catch {
            print("Error loading messages: \(error)")
            loadingProgress = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func fetchAllThreadIds() async throws -> [String] {
        var allThreadIds: [String] = []
        var pageToken: String? = nil
        var totalFetched = 0
        
        repeat {
            let (threadIds, nextToken) = try await gmailService.listThreads(maxResults: 100, pageToken: pageToken)
            allThreadIds.append(contentsOf: threadIds)
            pageToken = nextToken
            
            totalFetched += threadIds.count
            loadingProgress = "Fetching threads... (\(totalFetched) found)"
            
            // Small delay to avoid rate limiting
            if pageToken != nil {
                try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            }
        } while pageToken != nil
        
        return allThreadIds
    }
    
    private func loadThreadsInBatches(threadIds: [String]) async {
        let batchSize = 10
        var loadedCount = 0
        let totalCount = threadIds.count
        
        var threadDict: [String: EmailThread] = [:]
        
        for i in stride(from: 0, to: threadIds.count, by: batchSize) {
            let endIndex = min(i + batchSize, threadIds.count)
            let batch = Array(threadIds[i..<endIndex])
            
            await withTaskGroup(of: (String, [EmailMessage])?.self) { group in
                for threadId in batch {
                    group.addTask {
                        do {
                            let messages = try await self.gmailService.getThread(id: threadId)
                            return (threadId, messages)
                        } catch {
                            print("Error loading thread \(threadId): \(error)")
                            return nil
                        }
                    }
                }
                
                for await result in group {
                    if let (threadId, messages) = result, !messages.isEmpty {
                        // Create thread from messages
                        let thread = self.createThreadFromMessages(messages, threadId: threadId)
                        if let thread = thread {
                            let key = thread.id
                            
                            // Merge messages with existing thread if it exists
                            if let existingThread = threadDict[key] {
                                // Merge messages from both threads, removing duplicates
                                let allMessages = existingThread.messages + thread.messages
                                let uniqueMessages = Array(Set(allMessages)).sorted { $0.date < $1.date }
                                threadDict[key] = EmailThread(id: key, messages: uniqueMessages)
                            } else {
                                threadDict[key] = thread
                            }
                        }
                    }
                }
            }
            
            loadedCount += batch.count
            syncProgress = Double(loadedCount) / Double(totalCount)
            loadingProgress = "Loading conversations... \(loadedCount)/\(totalCount)"
            
            // Update threads periodically for better UX
            if i % 50 == 0 || endIndex == threadIds.count {
                threads = threadDict.values
                    .sorted { ($0.lastMessage?.date ?? Date.distantPast) > ($1.lastMessage?.date ?? Date.distantPast) }
            }
        }
        
        // Final update
        threads = threadDict.values
            .sorted { ($0.lastMessage?.date ?? Date.distantPast) > ($1.lastMessage?.date ?? Date.distantPast) }
    }
    
    private func createThreadFromMessages(_ messages: [EmailMessage], threadId: String) -> EmailThread? {
        guard !messages.isEmpty else { return nil }
        
        // Extract all participants from the messages
        let participants = extractParticipants(from: messages)
        
        // Determine if this is a group conversation
        let isGroupConversation = participants.count > 1
        
        // Generate a consistent thread ID based on participants
        let consistentThreadId = generateThreadId(from: participants, isGroup: isGroupConversation)
        
        return EmailThread(
            id: consistentThreadId,
            messages: messages.sorted { $0.date < $1.date }
        )
    }
    
    func sendMessage(to recipient: String, cc: String? = nil, subject: String, body: String, inReplyTo threadId: String? = nil) async -> EmailMessage? {
        do {
            // Send the message
            try await gmailService.sendMessage(to: recipient, cc: cc, subject: subject, body: body)
            
            // Wait a moment for Gmail to process
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Parse all recipients to determine thread ID
            var allParticipants = Set<String>()
            let userEmail = AuthenticationManager.shared.userEmail?.lowercased() ?? ""
            
            // Add To recipients
            let toRecipients = recipient.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            for toRecipient in toRecipients {
                let email = extractEmail(from: toRecipient).lowercased()
                if !email.isEmpty && email != userEmail && email.contains("@") {
                    allParticipants.insert(email)
                }
            }
            
            // Add CC recipients
            if let cc = cc, !cc.isEmpty {
                let ccRecipients = cc.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                for ccRecipient in ccRecipients {
                    let email = extractEmail(from: ccRecipient).lowercased()
                    if !email.isEmpty && email != userEmail && email.contains("@") {
                        allParticipants.insert(email)
                    }
                }
            }
            
            // Generate consistent thread ID
            let isGroupConversation = allParticipants.count > 1
            let consistentThreadId = generateThreadId(from: allParticipants, isGroup: isGroupConversation)
            
            // Fetch the sent message to get the actual ID
            let (sentMessageIds, _) = try await gmailService.listMessages(query: "in:sent to:\(toRecipients.first ?? "")", maxResults: 1)
            
            var sentMessage: EmailMessage? = nil
            
            if let latestMessageId = sentMessageIds.first {
                sentMessage = try await gmailService.getMessage(id: latestMessageId)
            }
            
            // If we couldn't fetch the sent message, create a temporary one
            if sentMessage == nil {
                sentMessage = EmailMessage(
                    id: UUID().uuidString,
                    threadId: threadId ?? UUID().uuidString,
                    from: AuthenticationManager.shared.userEmail ?? "Me",
                    fromEmail: AuthenticationManager.shared.userEmail ?? "",
                    to: recipient,
                    cc: cc,
                    bcc: nil,
                    subject: subject,
                    body: body,
                    snippet: String(body.prefix(100)),
                    date: Date(),
                    isRead: true,
                    labelIds: ["SENT"]
                )
            }
            
            // Update or create thread
            if let message = sentMessage {
                if let existingThreadIndex = threads.firstIndex(where: { $0.id == consistentThreadId }) {
                    // Add to existing thread
                    threads[existingThreadIndex].messages.append(message)
                    threads[existingThreadIndex].messages.sort { $0.date < $1.date }
                    
                    // Move thread to top
                    let updatedThread = threads.remove(at: existingThreadIndex)
                    threads.insert(updatedThread, at: 0)
                } else {
                    // Create new thread
                    let newThread = EmailThread(id: consistentThreadId, messages: [message])
                    threads.insert(newThread, at: 0)
                }
            }
            
            return sentMessage
            
        } catch {
            print("Error sending message: \(error)")
            return nil
        }
    }
    
    func archiveThread(_ thread: EmailThread) async {
        // Archive all messages in the thread
        for message in thread.messages {
            do {
                try await gmailService.archiveMessage(messageId: message.id)
            } catch {
                print("Error archiving message: \(error)")
            }
        }
        
        // Remove thread from the list
        threads.removeAll { $0.id == thread.id }
    }
    
    func deleteThreads(at offsets: IndexSet, from threads: [EmailThread]) async {
        for index in offsets {
            let thread = threads[index]
            for message in thread.messages {
                do {
                    try await gmailService.deleteMessage(messageId: message.id)
                } catch {
                    print("Error deleting message: \(error)")
                }
            }
        }
        
        // Reload to reflect changes
        await loadMessages()
    }
    
    func markThreadAsRead(_ thread: EmailThread) async {
        for message in thread.messages {
            if thread.unreadCount > 0 && !message.isRead {
                do {
                    try await gmailService.markAsRead(messageId: message.id)
                } catch {
                    print("Error marking message as read: \(error)")
                }
            }
        }
        
        // Update the thread's messages locally
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            for i in 0..<threads[index].messages.count {
                threads[index].messages[i] = EmailMessage(
                    id: threads[index].messages[i].id,
                    threadId: threads[index].messages[i].threadId,
                    from: threads[index].messages[i].from,
                    fromEmail: threads[index].messages[i].fromEmail,
                    to: threads[index].messages[i].to,
                    cc: threads[index].messages[i].cc,
                    bcc: threads[index].messages[i].bcc,
                    subject: threads[index].messages[i].subject,
                    body: threads[index].messages[i].body,
                    snippet: threads[index].messages[i].snippet,
                    date: threads[index].messages[i].date,
                    isRead: true,
                    labelIds: threads[index].messages[i].labelIds
                )
            }
        }
    }
    
    private func extractEmail(from emailString: String) -> String {
        if let range = emailString.range(of: #"<(.+?)>"#, options: .regularExpression) {
            return String(emailString[range]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        }
        if emailString.contains("@") {
            return emailString
        }
        return emailString
    }
}