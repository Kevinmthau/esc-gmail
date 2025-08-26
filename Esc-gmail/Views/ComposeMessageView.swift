import SwiftUI

struct ComposeMessageView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var conversationManager: ConversationManager
    @State private var recipient = ""
    @State private var ccRecipient = ""
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var isSending = false
    @State private var showCCField = false
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case recipient
        case cc
        case subject
        case body
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text("To:")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                        
                        TextField("Email address (separate multiple with commas)", text: $recipient)
                            .font(.body)
                            .textFieldStyle(PlainTextFieldStyle())
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .focused($focusedField, equals: .recipient)
                        
                        Button(action: { showCCField.toggle() }) {
                            Image(systemName: showCCField ? "minus.circle.fill" : "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    
                    Divider()
                    
                    if showCCField {
                        HStack {
                            Text("CC:")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .trailing)
                            
                            TextField("CC recipients (separate multiple with commas)", text: $ccRecipient)
                                .font(.body)
                                .textFieldStyle(PlainTextFieldStyle())
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                                .focused($focusedField, equals: .cc)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        
                        Divider()
                    }
                    
                    HStack {
                        Text("Subject:")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                        
                        TextField("Subject", text: $subject)
                            .font(.body)
                            .textFieldStyle(PlainTextFieldStyle())
                            .focused($focusedField, equals: .subject)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    
                    Divider()
                }
                .background(Color(.secondarySystemBackground))
                
                TextEditor(text: $messageBody)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .focused($focusedField, equals: .body)
                
                Spacer()
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        Task {
                            await sendMessage()
                        }
                    }
                    .disabled(recipient.isEmpty || subject.isEmpty || messageBody.isEmpty || isSending)
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
        }
    }
    
    @MainActor
    private func sendMessage() async {
        isSending = true
        
        // Send the message
        let sentMessage = await conversationManager.sendMessage(
            to: recipient,
            cc: ccRecipient.isEmpty ? nil : ccRecipient,
            subject: subject,
            body: messageBody
        )
        
        if sentMessage != nil {
            dismiss()
        }
        
        isSending = false
    }
}