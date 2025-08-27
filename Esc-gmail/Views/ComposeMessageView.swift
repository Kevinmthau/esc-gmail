import SwiftUI
import Contacts

struct ComposeMessageView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var conversationManager: ConversationManager
    @StateObject private var contactsManager = ContactsManager.shared
    
    @State private var recipientSearchText = ""
    @State private var selectedRecipients: [RecipientItem] = []
    @State private var messageBody = ""
    @State private var isSending = false
    @State private var showingContactResults = false
    @State private var searchResults: [CNContact] = []
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case recipient
        case body
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Recipients Section
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 0) {
                        Text("To:")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(width: 40)
                            .padding(.leading, 16)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .center, spacing: 6) {
                                // Selected recipients chips
                                ForEach(selectedRecipients) { recipient in
                                    RecipientChip(recipient: recipient) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedRecipients.removeAll { $0.id == recipient.id }
                                        }
                                    }
                                }
                                
                                // Search field
                                TextField("", text: $recipientSearchText)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                                    .disableAutocorrection(true)
                                    .focused($focusedField, equals: .recipient)
                                    .frame(width: max(100, CGFloat(200 - (selectedRecipients.count * 40))))
                                    .fixedSize(horizontal: true, vertical: false)
                                    .onChange(of: recipientSearchText) { oldValue, newValue in
                                        if !newValue.isEmpty {
                                            Task {
                                                await searchContacts(query: newValue)
                                            }
                                            showingContactResults = true
                                        } else {
                                            showingContactResults = false
                                            searchResults = []
                                        }
                                    }
                                    .onSubmit {
                                        addRecipientFromText()
                                    }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 8)
                        }
                        
                        // Add contact button
                        Button(action: {
                            // TODO: Show contact picker
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 24))
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    Divider()
                }
                .background(Color(.systemBackground))
                
                // Contact search results overlay on top
                if showingContactResults && !searchResults.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(searchResults, id: \.identifier) { contact in
                                ContactSearchRow(contact: contact) { selectedContact, email in
                                    addRecipient(contact: selectedContact, email: email)
                                    recipientSearchText = ""
                                    searchResults = []
                                    showingContactResults = false
                                }
                                
                                if contact != searchResults.last {
                                    Divider()
                                        .padding(.leading, 60)
                                }
                            }
                        }
                    }
                    .background(Color(.systemBackground))
                }
                
                // Message body with iMessage-style input
                if !showingContactResults || searchResults.isEmpty {
                    VStack {
                        Spacer()
                        
                        MessageComposer(
                            text: $messageBody, 
                            focusedField: _focusedField,
                            isEnabled: !selectedRecipients.isEmpty,
                            onSend: {
                                Task {
                                    await sendMessage()
                                }
                            }
                        )
                    }
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .disabled(isSending)
            .overlay {
                if isSending {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ProgressView("Sending...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 5)
                }
            }
        }
        .onAppear {
            focusedField = .recipient
            
            // Request contacts access if needed
            if contactsManager.authorizationStatus == .notDetermined {
                Task {
                    _ = await contactsManager.requestAccess()
                }
            }
        }
    }
    
    private func searchContacts(query: String) async {
        searchResults = await contactsManager.searchContacts(query: query)
    }
    
    private func addRecipientFromText() {
        let trimmed = recipientSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Check if it's an email
        if trimmed.contains("@") {
            let recipient = RecipientItem(
                name: extractName(from: trimmed),
                email: trimmed,
                phoneNumber: nil
            )
            
            if !selectedRecipients.contains(where: { $0.email == recipient.email }) {
                selectedRecipients.append(recipient)
            }
            recipientSearchText = ""
        }
    }
    
    private func addRecipient(contact: CNContact, email: String) {
        let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        let recipient = RecipientItem(
            name: fullName.isEmpty ? extractName(from: email) : fullName,
            email: email,
            phoneNumber: nil
        )
        
        if !selectedRecipients.contains(where: { $0.email == recipient.email }) {
            selectedRecipients.append(recipient)
        }
    }
    
    private func extractName(from email: String) -> String {
        if let atIndex = email.firstIndex(of: "@") {
            return String(email[..<atIndex])
        }
        return email
    }
    
    @MainActor
    private func sendMessage() async {
        isSending = true
        
        // Create recipient string from selected recipients
        let recipientEmails = selectedRecipients.compactMap { $0.email }.joined(separator: ", ")
        
        // Send the message with no subject
        let sentMessage = await conversationManager.sendMessage(
            to: recipientEmails,
            cc: nil,
            subject: "",
            body: messageBody
        )
        
        if sentMessage != nil {
            dismiss()
        }
        
        isSending = false
    }
}

struct RecipientItem: Identifiable {
    let id = UUID()
    let name: String
    let email: String?
    let phoneNumber: String?
}

struct RecipientChip: View {
    let recipient: RecipientItem
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(recipient.name)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle()) // Disable default button haptics
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.blue)
        .cornerRadius(15)
    }
}

struct ContactSearchRow: View {
    let contact: CNContact
    let onSelect: (CNContact, String) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Show all email addresses for the contact
            ForEach(Array(contact.emailAddresses.enumerated()), id: \.offset) { index, emailAddress in
                Button(action: {
                    onSelect(contact, emailAddress.value as String)
                }) {
                    HStack(spacing: 12) {
                        // Contact image or initials
                        ZStack {
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 36, height: 36)
                            
                            if let imageData = contact.thumbnailImageData,
                               let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                            } else {
                                Text(initials(for: contact))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(contact.givenName) \(contact.familyName)")
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Text(emailAddress.value as String)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(Color(.systemGray3))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(PlainButtonStyle())
                
                if index < contact.emailAddresses.count - 1 {
                    Divider()
                        .padding(.leading, 64)
                }
            }
            
            // Show phone numbers if no emails
            if contact.emailAddresses.isEmpty {
                ForEach(Array(contact.phoneNumbers.enumerated()), id: \.offset) { index, phoneNumber in
                    HStack(spacing: 12) {
                        // Contact image or initials
                        ZStack {
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 36, height: 36)
                            
                            if let imageData = contact.thumbnailImageData,
                               let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                            } else {
                                Text(initials(for: contact))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(contact.givenName) \(contact.familyName)")
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Text(phoneNumber.value.stringValue)
                                .font(.system(size: 13))
                                .foregroundColor(.blue)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(Color(.systemGray3))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .opacity(0.5) // Disable phone numbers for now
                }
            }
        }
    }
    
    private func initials(for contact: CNContact) -> String {
        var initials = ""
        if let firstChar = contact.givenName.first {
            initials += String(firstChar)
        }
        if let firstChar = contact.familyName.first {
            initials += String(firstChar)
        }
        return initials.uppercased()
    }
}

struct MessageComposer: View {
    @Binding var text: String
    @FocusState var focusedField: ComposeMessageView.Field?
    let isEnabled: Bool
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {}) {
                Image(systemName: "plus")
                    .font(.system(size: 22))
                    .foregroundColor(.blue)
            }
            
            HStack {
                TextField("iMessage", text: $text, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .lineLimit(1...10)
                    .focused($focusedField, equals: .body)
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
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(text.isEmpty || !isEnabled ? .gray : .blue)
            }
            .disabled(text.isEmpty || !isEnabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}