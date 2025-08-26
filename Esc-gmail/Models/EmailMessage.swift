import Foundation

struct EmailMessage: Identifiable, Codable, Hashable {
    let id: String
    let threadId: String
    let from: String
    let fromEmail: String
    let to: String
    let cc: String?
    let bcc: String?
    let subject: String
    let body: String
    let snippet: String
    let date: Date
    let isRead: Bool
    let labelIds: [String]
    
    var isFromMe: Bool {
        fromEmail.lowercased() == AuthenticationManager.shared.userEmail?.lowercased()
    }
    
    var allRecipients: [String] {
        var recipients: [String] = []
        
        // Add To recipients
        recipients.append(contentsOf: parseEmailAddresses(from: to))
        
        // Add CC recipients
        if let cc = cc, !cc.isEmpty {
            recipients.append(contentsOf: parseEmailAddresses(from: cc))
        }
        
        // Add BCC recipients (though typically not visible)
        if let bcc = bcc, !bcc.isEmpty {
            recipients.append(contentsOf: parseEmailAddresses(from: bcc))
        }
        
        return recipients
    }
    
    var isGroupMessage: Bool {
        let recipients = allRecipients
        // Group message if there are more than 1 recipient (excluding the user)
        let userEmail = AuthenticationManager.shared.userEmail?.lowercased() ?? ""
        let otherRecipients = recipients.filter { extractEmailAddress(from: $0).lowercased() != userEmail }
        return otherRecipients.count > 1
    }
    
    private func parseEmailAddresses(from string: String) -> [String] {
        return string.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    }
    
    private func extractEmailAddress(from string: String) -> String {
        if let startIndex = string.firstIndex(of: "<"),
           let endIndex = string.firstIndex(of: ">") {
            let range = string.index(after: startIndex)..<endIndex
            return String(string[range])
        }
        return string
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: EmailMessage, rhs: EmailMessage) -> Bool {
        lhs.id == rhs.id
    }
}

struct EmailThread: Identifiable {
    let id: String
    var messages: [EmailMessage]
    
    var participants: String {
        let userEmail = AuthenticationManager.shared.userEmail?.lowercased() ?? ""
        
        // Check if this is a group conversation
        if isGroupConversation {
            // For group messages, show all participants' first names
            var allParticipants = Set<String>()
            
            for message in messages {
                // Add sender if not the user
                if !message.isFromMe {
                    // Extract first name from sender
                    let firstName = extractFirstName(from: message.from)
                    allParticipants.insert(firstName)
                }
                
                // Add all recipients
                for recipient in message.allRecipients {
                    let email = extractEmailAddress(from: recipient).lowercased()
                    if email != userEmail {
                        let firstName = extractFirstName(from: recipient)
                        allParticipants.insert(firstName)
                    }
                }
            }
            
            // Sort the first names alphabetically
            let sortedParticipants = Array(allParticipants).sorted()
            
            // If more than 5 participants, show first 5 and count
            if sortedParticipants.count > 5 {
                let firstFive = sortedParticipants.prefix(5)
                return firstFive.joined(separator: ", ") + " +\(sortedParticipants.count - 5)"
            }
            return sortedParticipants.joined(separator: ", ")
        } else {
            // For single conversations, show the other person's first name
            var uniqueParticipants = Set<String>()
            for message in messages {
                if message.isFromMe {
                    // Parse recipients and exclude the user
                    let recipients = parseRecipients(from: message.to)
                    for recipient in recipients {
                        let email = extractEmailAddress(from: recipient).lowercased()
                        if email != userEmail {
                            uniqueParticipants.insert(extractFirstName(from: recipient))
                        }
                    }
                } else {
                    // Check if sender is not the user
                    let senderEmail = extractEmailAddress(from: message.fromEmail).lowercased()
                    if senderEmail != userEmail {
                        uniqueParticipants.insert(extractFirstName(from: message.from))
                    }
                }
            }
            
            if uniqueParticipants.isEmpty {
                return "Me"
            }
            return uniqueParticipants.joined(separator: ", ")
        }
    }
    
    // This method can be called from MainActor context to get contact names
    @MainActor
    func getParticipantsWithContacts() -> String {
        let userEmail = AuthenticationManager.shared.userEmail?.lowercased() ?? ""
        let contactsManager = ContactsManager.shared
        
        if isGroupConversation {
            // For group conversations, get first names from address book
            var participantEmails = Set<String>()
            
            // Collect all unique participant emails
            for message in messages {
                if !message.isFromMe {
                    let senderEmail = message.fromEmail.lowercased()
                    if !senderEmail.isEmpty && senderEmail != userEmail {
                        participantEmails.insert(senderEmail)
                    }
                }
                
                for recipient in message.allRecipients {
                    let email = extractEmailAddress(from: recipient).lowercased()
                    if !email.isEmpty && email != userEmail && email.contains("@") {
                        participantEmails.insert(email)
                    }
                }
            }
            
            // Get first names from contacts or fallback - use Array to allow duplicates
            var firstNames: [String] = []
            for email in participantEmails {
                if let contact = contactsManager.getContact(for: email),
                   !contact.givenName.isEmpty {
                    firstNames.append(contact.givenName)
                } else {
                    // Fallback to extracting from message data
                    if let message = messages.first(where: { 
                        $0.fromEmail.lowercased() == email || 
                        $0.allRecipients.contains(where: { extractEmailAddress(from: $0).lowercased() == email })
                    }) {
                        let nameString = message.fromEmail.lowercased() == email ? message.from : 
                            message.allRecipients.first(where: { extractEmailAddress(from: $0).lowercased() == email }) ?? email
                        firstNames.append(extractFirstName(from: nameString))
                    } else {
                        firstNames.append(extractFirstName(from: email))
                    }
                }
            }
            
            let sortedNames = firstNames.sorted()
            if sortedNames.count > 5 {
                return sortedNames.prefix(5).joined(separator: ", ") + " +\(sortedNames.count - 5)"
            }
            return sortedNames.joined(separator: ", ")
        } else {
            // For individual conversations, try to get full contact name
            for message in messages {
                if message.isFromMe {
                    let recipients = parseRecipients(from: message.to)
                    for recipient in recipients {
                        let email = extractEmailAddress(from: recipient).lowercased()
                        if email != userEmail {
                            if let contact = contactsManager.getContact(for: email),
                               !contact.givenName.isEmpty {
                                return contact.givenName
                            }
                            return extractFirstName(from: recipient)
                        }
                    }
                } else {
                    let senderEmail = message.fromEmail.lowercased()
                    if senderEmail != userEmail {
                        if let contact = contactsManager.getContact(for: senderEmail),
                           !contact.givenName.isEmpty {
                            return contact.givenName
                        }
                        return extractFirstName(from: message.from)
                    }
                }
            }
        }
        
        return "Me"
    }
    
    private func parseRecipients(from recipientString: String) -> [String] {
        // Split by comma to handle multiple recipients
        return recipientString.split(separator: ",").map { 
            $0.trimmingCharacters(in: .whitespacesAndNewlines) 
        }
    }
    
    private func extractEmailAddress(from emailString: String) -> String {
        // Extract email from "Name <email>" format
        if let startIndex = emailString.firstIndex(of: "<"),
           let endIndex = emailString.firstIndex(of: ">") {
            let range = emailString.index(after: startIndex)..<endIndex
            return String(emailString[range])
        }
        // Return as-is if it's already just an email
        return emailString
    }
    
    private func extractName(from emailString: String) -> String {
        // If it's in "Name <email>" format, extract the name
        if let nameEndIndex = emailString.firstIndex(of: "<") {
            let name = emailString[..<nameEndIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return name
            }
        }
        // If no name, extract email username (part before @)
        let email = extractEmailAddress(from: emailString)
        if let atIndex = email.firstIndex(of: "@") {
            return String(email[..<atIndex])
        }
        return email
    }
    
    private func extractFirstName(from emailString: String) -> String {
        // First try to get the full name
        let fullName = extractName(from: emailString)
        
        // Split by space and take the first component
        let nameComponents = fullName.split(separator: " ")
        if let firstName = nameComponents.first {
            return String(firstName)
        }
        
        return fullName
    }
    
    var isGroupConversation: Bool {
        // Check if the thread ID indicates a group conversation
        if id.hasPrefix("group-") {
            return true
        }
        
        // Also check if any messages indicate multiple recipients
        let userEmail = AuthenticationManager.shared.userEmail?.lowercased() ?? ""
        var allParticipants = Set<String>()
        
        for message in messages {
            // Add sender if not the user
            if !message.isFromMe && !message.fromEmail.isEmpty {
                allParticipants.insert(message.fromEmail.lowercased())
            }
            
            // Add all recipients
            for recipient in message.allRecipients {
                let email = extractEmailAddress(from: recipient).lowercased()
                if email != userEmail && email.contains("@") {
                    allParticipants.insert(email)
                }
            }
        }
        
        return allParticipants.count > 1
    }
    
    var lastMessage: EmailMessage? {
        messages.max { $0.date < $1.date }
    }
    
    var unreadCount: Int {
        messages.filter { !$0.isRead }.count
    }
}