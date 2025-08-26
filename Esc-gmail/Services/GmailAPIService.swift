import Foundation

class GmailAPIService {
    static let shared = GmailAPIService()
    private let baseURL = "https://gmail.googleapis.com/gmail/v1"
    private let apiKey = "AIzaSyAnVWdfhCGB0raSuwStoMl6U3368E9-gxk"
    
    private func makeRequest(endpoint: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let token = AuthenticationManager.shared.accessToken else {
            throw GmailAPIError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw GmailAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw GmailAPIError.requestFailed
        }
        
        return data
    }
    
    func listMessages(query: String? = nil, maxResults: Int = 50, pageToken: String? = nil) async throws -> (messageIds: [String], nextPageToken: String?) {
        var endpoint = "users/me/messages?maxResults=\(maxResults)"
        
        if let query = query {
            endpoint += "&q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        
        if let pageToken = pageToken {
            endpoint += "&pageToken=\(pageToken)"
        }
        
        let data = try await makeRequest(endpoint: endpoint)
        let response = try JSONDecoder().decode(MessageListResponse.self, from: data)
        return (response.messages?.map { $0.id } ?? [], response.nextPageToken)
    }
    
    func listAllMessages(query: String? = nil, progressHandler: ((Int) -> Void)? = nil) async throws -> [String] {
        var allMessageIds: [String] = []
        var pageToken: String? = nil
        var totalFetched = 0
        
        repeat {
            let (messageIds, nextToken) = try await listMessages(query: query, maxResults: 100, pageToken: pageToken)
            allMessageIds.append(contentsOf: messageIds)
            pageToken = nextToken
            
            totalFetched += messageIds.count
            progressHandler?(totalFetched)
            
            // Add a small delay to avoid rate limiting
            if pageToken != nil {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        } while pageToken != nil
        
        return allMessageIds
    }
    
    func listThreads(query: String? = nil, maxResults: Int = 50, pageToken: String? = nil) async throws -> (threadIds: [String], nextPageToken: String?) {
        var endpoint = "users/me/threads?maxResults=\(maxResults)"
        
        if let query = query {
            endpoint += "&q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        
        if let pageToken = pageToken {
            endpoint += "&pageToken=\(pageToken)"
        }
        
        let data = try await makeRequest(endpoint: endpoint)
        let response = try JSONDecoder().decode(ThreadListResponse.self, from: data)
        return (response.threads?.map { $0.id } ?? [], response.nextPageToken)
    }
    
    
    func getMessage(id: String) async throws -> EmailMessage {
        let endpoint = "users/me/messages/\(id)"
        let data = try await makeRequest(endpoint: endpoint)
        let gmailMessage = try JSONDecoder().decode(GmailMessage.self, from: data)
        return gmailMessage.toEmailMessage()
    }
    
    func getThread(id: String) async throws -> [EmailMessage] {
        let endpoint = "users/me/threads/\(id)"
        let data = try await makeRequest(endpoint: endpoint)
        let thread = try JSONDecoder().decode(GmailThread.self, from: data)
        return thread.messages.map { $0.toEmailMessage() }
    }
    
    func sendMessage(to: String, cc: String? = nil, subject: String, body: String) async throws {
        let message = createMimeMessage(to: to, cc: cc, subject: subject, body: body)
        let rawMessage = message.data(using: .utf8)?.base64EncodedString() ?? ""
        
        let requestBody = ["raw": rawMessage.replacingOccurrences(of: "+", with: "-")
                                          .replacingOccurrences(of: "/", with: "_")
                                          .replacingOccurrences(of: "=", with: "")]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        _ = try await makeRequest(endpoint: "users/me/messages/send", method: "POST", body: jsonData)
    }
    
    func markAsRead(messageId: String) async throws {
        let requestBody = ["removeLabelIds": ["UNREAD"]]
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        _ = try await makeRequest(endpoint: "users/me/messages/\(messageId)/modify", method: "POST", body: jsonData)
    }
    
    func archiveMessage(messageId: String) async throws {
        let requestBody = ["removeLabelIds": ["INBOX"]]
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        _ = try await makeRequest(endpoint: "users/me/messages/\(messageId)/modify", method: "POST", body: jsonData)
    }
    
    func deleteMessage(messageId: String) async throws {
        _ = try await makeRequest(endpoint: "users/me/messages/\(messageId)/trash", method: "POST")
    }
    
    func archiveThread(threadId: String) async throws {
        // Archive all messages in the thread
        let messages = try await getThread(id: threadId)
        for message in messages {
            try await archiveMessage(messageId: message.id)
        }
    }
    
    private func createMimeMessage(to: String, cc: String? = nil, subject: String, body: String) -> String {
        let from = AuthenticationManager.shared.userEmail ?? ""
        var message = """
        From: \(from)
        To: \(to)
        """
        
        if let cc = cc, !cc.isEmpty {
            message += "\nCc: \(cc)"
        }
        
        message += """
        
        Subject: \(subject)
        
        \(body)
        """
        return message
    }
}

enum GmailAPIError: Error {
    case notAuthenticated
    case invalidURL
    case requestFailed
    case decodingError
}

struct MessageListResponse: Codable {
    let messages: [MessageItem]?
    let nextPageToken: String?
}

struct MessageItem: Codable {
    let id: String
    let threadId: String
}

struct ThreadListResponse: Codable {
    let threads: [ThreadItem]?
    let nextPageToken: String?
}

struct ThreadItem: Codable {
    let id: String
}

struct GmailMessage: Codable {
    let id: String
    let threadId: String
    let labelIds: [String]?
    let snippet: String
    let payload: Payload
    let internalDate: String?
    
    func toEmailMessage() -> EmailMessage {
        let headers = payload.headers ?? []
        let from = headers.first { $0.name == "From" }?.value ?? ""
        let to = headers.first { $0.name == "To" }?.value ?? ""
        let cc = headers.first { $0.name == "Cc" }?.value
        let bcc = headers.first { $0.name == "Bcc" }?.value
        let subject = headers.first { $0.name == "Subject" }?.value ?? ""
        
        let fromEmail = extractEmail(from: from)
        let fromName = extractName(from: from)
        
        let body = extractBody(from: payload)
        
        // Use internalDate which is in milliseconds since epoch
        let messageDate: Date
        if let internalDateString = internalDate,
           let timestamp = Double(internalDateString) {
            // Convert milliseconds to seconds
            messageDate = Date(timeIntervalSince1970: timestamp / 1000)
        } else {
            // Fallback to Date header if internalDate is not available
            let dateHeader = headers.first { $0.name == "Date" }?.value ?? ""
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
            messageDate = dateFormatter.date(from: dateHeader) ?? Date()
        }
        
        return EmailMessage(
            id: id,
            threadId: threadId,
            from: fromName,
            fromEmail: fromEmail,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            body: body,
            snippet: snippet,
            date: messageDate,
            isRead: !(labelIds?.contains("UNREAD") ?? false),
            labelIds: labelIds ?? []
        )
    }
    
    private func extractEmail(from string: String) -> String {
        if let range = string.range(of: #"<(.+?)>"#, options: .regularExpression) {
            return String(string[range]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        }
        return string
    }
    
    private func extractName(from string: String) -> String {
        if let range = string.range(of: #"^[^<]+"#, options: .regularExpression) {
            return String(string[range]).trimmingCharacters(in: .whitespaces)
        }
        return string
    }
    
    private func extractBody(from payload: Payload) -> String {
        if let data = payload.body?.data {
            return decodeBase64(data)
        }
        
        if let parts = payload.parts {
            for part in parts {
                if part.mimeType == "text/plain", let data = part.body?.data {
                    return decodeBase64(data)
                }
            }
            
            for part in parts {
                if part.mimeType == "text/html", let data = part.body?.data {
                    let html = decodeBase64(data)
                    return stripHTML(html)
                }
            }
        }
        
        return ""
    }
    
    private func decodeBase64(_ string: String) -> String {
        let base64 = string.replacingOccurrences(of: "-", with: "+")
                          .replacingOccurrences(of: "_", with: "/")
        
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let result = String(data: data, encoding: .utf8) else {
            return ""
        }
        
        return result
    }
    
    private func stripHTML(_ html: String) -> String {
        var text = html
        
        // Replace common HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "<br/>", with: "\n")
        text = text.replacingOccurrences(of: "<br />", with: "\n")
        text = text.replacingOccurrences(of: "</p>", with: "\n")
        text = text.replacingOccurrences(of: "</div>", with: "\n")
        
        // Remove all HTML tags
        let pattern = "<[^>]+>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        text = regex?.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "") ?? text
        
        // Clean up extra whitespace
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GmailThread: Codable {
    let id: String
    let messages: [GmailMessage]
}

struct Payload: Codable {
    let headers: [Header]?
    let body: Body?
    let parts: [Part]?
}

struct Header: Codable {
    let name: String
    let value: String
}

struct Body: Codable {
    let data: String?
}

struct Part: Codable {
    let mimeType: String
    let body: Body?
}