import Foundation
import Contacts
import SwiftUI

@MainActor
class ContactsManager: ObservableObject {
    static let shared = ContactsManager()
    
    private let contactStore = CNContactStore()
    private var contactsCache: [String: CNContact] = [:]
    @Published var authorizationStatus: CNAuthorizationStatus = .notDetermined
    
    private init() {
        checkAuthorizationStatus()
    }
    
    private func checkAuthorizationStatus() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }
    
    func requestAccess() async -> Bool {
        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            await MainActor.run {
                authorizationStatus = granted ? .authorized : .denied
            }
            return granted
        } catch {
            print("Error requesting contacts access: \(error)")
            return false
        }
    }
    
    func getContact(for email: String) -> CNContact? {
        // Check cache first
        let normalizedEmail = email.lowercased()
        if let cachedContact = contactsCache[normalizedEmail] {
            return cachedContact
        }
        
        // If not authorized, return nil
        guard authorizationStatus == .authorized else {
            return nil
        }
        
        // Search for contact by email
        let keysToFetch = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactMiddleNameKey,
            CNContactNamePrefixKey,
            CNContactNameSuffixKey,
            CNContactNicknameKey,
            CNContactOrganizationNameKey,
            CNContactEmailAddressesKey,
            CNContactImageDataKey,
            CNContactThumbnailImageDataKey,
            CNContactImageDataAvailableKey
        ] as [CNKeyDescriptor]
        
        let predicate = CNContact.predicateForContacts(matchingEmailAddress: normalizedEmail)
        
        do {
            let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            if let contact = contacts.first {
                // Cache the result
                contactsCache[normalizedEmail] = contact
                return contact
            }
        } catch {
            print("Error fetching contact for email \(email): \(error)")
        }
        
        return nil
    }
    
    func getContactName(for email: String) -> String? {
        guard let contact = getContact(for: email) else {
            return nil
        }
        
        // Build name from components we fetched
        var nameComponents: [String] = []
        
        if !contact.givenName.isEmpty {
            nameComponents.append(contact.givenName)
        }
        
        if !contact.familyName.isEmpty {
            nameComponents.append(contact.familyName)
        }
        
        if nameComponents.isEmpty {
            // Try to get organization name as fallback
            return nil
        }
        
        return nameComponents.joined(separator: " ")
    }
    
    func getContactImage(for email: String) -> Image? {
        guard let contact = getContact(for: email) else {
            return nil
        }
        
        // Try thumbnail first (smaller, faster)
        if contact.isKeyAvailable(CNContactThumbnailImageDataKey),
           let thumbnailData = contact.thumbnailImageData,
           let uiImage = UIImage(data: thumbnailData) {
            return Image(uiImage: uiImage)
        }
        
        // Fall back to full image
        if contact.isKeyAvailable(CNContactImageDataAvailableKey),
           contact.imageDataAvailable,
           contact.isKeyAvailable(CNContactImageDataKey),
           let imageData = contact.imageData,
           let uiImage = UIImage(data: imageData) {
            return Image(uiImage: uiImage)
        }
        
        return nil
    }
    
    func getContactInitials(for email: String) -> String {
        if let contact = getContact(for: email) {
            var initials = ""
            
            // Safely check for available keys
            if contact.isKeyAvailable(CNContactGivenNameKey) && !contact.givenName.isEmpty {
                initials += contact.givenName.first?.uppercased() ?? ""
            }
            
            if contact.isKeyAvailable(CNContactFamilyNameKey) && !contact.familyName.isEmpty {
                initials += contact.familyName.first?.uppercased() ?? ""
            }
            
            if !initials.isEmpty {
                return initials
            }
        }
        
        // Fall back to email initial
        return email.first?.uppercased() ?? "?"
    }
    
    func refreshCache() {
        contactsCache.removeAll()
    }
    
    // Search contacts by name or email (async to avoid blocking main thread)
    func searchContacts(query: String) async -> [CNContact] {
        guard authorizationStatus == .authorized else { return [] }
        guard !query.isEmpty else { return [] }
        
        let store = contactStore  // Capture the store before detached task
        
        return await withCheckedContinuation { continuation in
            Task.detached {
                let keysToFetch = [
                    CNContactGivenNameKey,
                    CNContactFamilyNameKey,
                    CNContactEmailAddressesKey,
                    CNContactPhoneNumbersKey,
                    CNContactThumbnailImageDataKey,
                    CNContactImageDataAvailableKey
                ] as [CNKeyDescriptor]
                
                var results: [CNContact] = []
                
                do {
                    // Search by name
                    let namePredicate = CNContact.predicateForContacts(matchingName: query)
                    let nameContacts = try store.unifiedContacts(matching: namePredicate, keysToFetch: keysToFetch)
                    results.append(contentsOf: nameContacts)
                    
                    // Also search all contacts and filter by email containing query
                    let request = CNContactFetchRequest(keysToFetch: keysToFetch)
                    try store.enumerateContacts(with: request) { contact, _ in
                        // Check if email contains query
                        for email in contact.emailAddresses {
                            let emailString = email.value as String
                            if emailString.lowercased().contains(query.lowercased()) {
                                if !results.contains(where: { $0.identifier == contact.identifier }) {
                                    results.append(contact)
                                }
                                break
                            }
                        }
                        
                        // Check if name contains query (for partial matches not caught by predicate)
                        let fullName = "\(contact.givenName) \(contact.familyName)".lowercased()
                        if fullName.contains(query.lowercased()) {
                            if !results.contains(where: { $0.identifier == contact.identifier }) {
                                results.append(contact)
                            }
                        }
                    }
                } catch {
                    print("Error searching contacts: \(error)")
                }
                
                continuation.resume(returning: results)
            }
        }
    }
    
    // Batch fetch for performance
    func preloadContacts(for emails: [String]) {
        guard authorizationStatus == .authorized else { return }
        
        let uniqueEmails = Set(emails.map { $0.lowercased() })
        
        for email in uniqueEmails {
            if contactsCache[email] == nil {
                _ = getContact(for: email)
            }
        }
    }
}