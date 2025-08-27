import SwiftUI

struct ConversationListView: View {
    @StateObject private var conversationManager = ConversationManager.shared
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var searchText = ""
    @State private var showingCompose = false
    
    var body: some View {
        if !authManager.isSignedIn {
            SignInView()
                .environmentObject(authManager)
        } else {
            NavigationView {
                VStack(spacing: 0) {
                    if conversationManager.isLoading && conversationManager.threads.isEmpty {
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(1.5)
                            
                            Text(conversationManager.loadingProgress)
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            if conversationManager.syncProgress > 0 && conversationManager.syncProgress < 1 && !conversationManager.syncProgress.isNaN && !conversationManager.syncProgress.isInfinite {
                                ProgressView(value: conversationManager.syncProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .padding(.horizontal, 40)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(filteredThreads) { thread in
                                NavigationLink(destination: ConversationDetailView(thread: thread)
                                    .environmentObject(conversationManager)) {
                                    ConversationRow(thread: thread)
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        Task {
                                            await conversationManager.archiveThread(thread)
                                        }
                                    } label: {
                                        Label("Archive", systemImage: "archivebox")
                                    }
                                    .tint(.indigo)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        Task {
                                            await conversationManager.markThreadAsRead(thread)
                                        }
                                    } label: {
                                        Label(thread.unreadCount > 0 ? "Read" : "Unread", 
                                              systemImage: thread.unreadCount > 0 ? "envelope.open" : "envelope")
                                    }
                                    .tint(.blue)
                                }
                            }
                            .onDelete { indexSet in
                                Task {
                                    await conversationManager.deleteThreads(at: indexSet, from: filteredThreads)
                                }
                            }
                        }
                        .listStyle(PlainListStyle())
                        .refreshable {
                            await conversationManager.loadMessages()
                        }
                    }
                }
                .navigationTitle("Messages")
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $searchText, prompt: "Search")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Sign Out") {
                            authManager.signOut()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showingCompose = true
                        }) {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
            }
            .task {
                await conversationManager.loadMessages()
            }
            .sheet(isPresented: $showingCompose) {
                ComposeMessageView()
                    .environmentObject(conversationManager)
            }
        }
    }
    
    var filteredThreads: [EmailThread] {
        if searchText.isEmpty {
            return conversationManager.threads
        } else {
            return conversationManager.threads.filter { thread in
                thread.participants.localizedCaseInsensitiveContains(searchText) ||
                thread.lastMessage?.snippet.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }
}

struct ConversationRow: View {
    let thread: EmailThread
    @StateObject private var contactsManager = ContactsManager.shared
    @State private var participantNames: String = ""
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture or initials
            if thread.isGroupConversation {
                // Show group icon for group conversations with consistent color per group
                Circle()
                    .fill(backgroundColorForGroup(thread.id))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    )
            } else if let contactImage = getContactImage() {
                contactImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(backgroundColorForInitials)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(getContactInitials())
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(participantNames.isEmpty ? getParticipantName() : participantNames)
                        .font(.headline)
                        .fontWeight(thread.unreadCount > 0 ? .semibold : .regular)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text(formatDate(thread.lastMessage?.date ?? Date()))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }
                
                Text(thread.lastMessage?.snippet ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            if thread.unreadCount > 0 {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            loadParticipantNames()
        }
    }
    
    func loadParticipantNames() {
        if thread.isGroupConversation {
            participantNames = thread.getParticipantsWithContacts()
        } else {
            participantNames = getParticipantName()
        }
    }
    
    func getParticipantName() -> String {
        // For group conversations, get names from address book
        if thread.isGroupConversation {
            return thread.getParticipantsWithContacts()
        }
        
        // For individual conversations, try to get contact name
        if let primaryEmail = getPrimaryEmail(),
           let contactName = contactsManager.getContactName(for: primaryEmail) {
            return contactName
        }
        // Fallback to thread participants
        return thread.participants
    }
    
    func getContactImage() -> Image? {
        // Get the primary email for this thread
        if let primaryEmail = getPrimaryEmail() {
            return contactsManager.getContactImage(for: primaryEmail)
        }
        return nil
    }
    
    func getContactInitials() -> String {
        // Get initials from contact or fallback to thread participants
        if let primaryEmail = getPrimaryEmail() {
            let contactInitials = contactsManager.getContactInitials(for: primaryEmail)
            if contactInitials != primaryEmail.first?.uppercased() {
                return contactInitials
            }
        }
        
        // Fallback to parsing thread participants
        let names = thread.participants.split(separator: " ")
        if names.count >= 2 {
            return String(names[0].prefix(1)) + String(names[1].prefix(1))
        } else if !names.isEmpty {
            return String(names[0].prefix(2))
        }
        return "?"
    }
    
    func getPrimaryEmail() -> String? {
        // Get the email address of the primary participant (not the user)
        let userEmail = AuthenticationManager.shared.userEmail?.lowercased() ?? ""
        
        for message in thread.messages {
            if message.isFromMe {
                // Extract recipient email
                if message.to.contains("@") {
                    let email = extractEmailFromString(message.to)
                    if email.lowercased() != userEmail {
                        return email
                    }
                }
            } else {
                // Use sender email
                if message.fromEmail.lowercased() != userEmail {
                    return message.fromEmail
                }
            }
        }
        return nil
    }
    
    func extractEmailFromString(_ string: String) -> String {
        if let startIndex = string.firstIndex(of: "<"),
           let endIndex = string.firstIndex(of: ">") {
            let range = string.index(after: startIndex)..<endIndex
            return String(string[range])
        }
        return string.trimmingCharacters(in: .whitespaces)
    }
    
    var backgroundColorForInitials: Color {
        // Generate a consistent color based on the thread ID
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .teal, .indigo]
        let hash = thread.id.hashValue
        let index = abs(hash) % colors.count
        return colors[index]
    }
    
    func backgroundColorForGroup(_ groupId: String) -> Color {
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
    
    func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.timeZone = TimeZone.current
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.dateComponents([.day], from: date, to: now).day! < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            formatter.timeZone = TimeZone.current
            return formatter.string(from: date)
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            formatter.timeZone = TimeZone.current
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeZone = TimeZone.current
            return formatter.string(from: date)
        }
    }
}

