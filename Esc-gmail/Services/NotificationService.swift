import Foundation
import UserNotifications
import BackgroundTasks

class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()
    
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 30
    private var notifiedMessageIds: Set<String> = []
    private let notifiedMessagesKey = "NotifiedMessageIds"
    
    override init() {
        super.init()
        setupNotifications()
        loadNotifiedMessages()
    }
    
    private func loadNotifiedMessages() {
        if let savedIds = UserDefaults.standard.array(forKey: notifiedMessagesKey) as? [String] {
            notifiedMessageIds = Set(savedIds)
        }
    }
    
    private func saveNotifiedMessages() {
        UserDefaults.standard.set(Array(notifiedMessageIds), forKey: notifiedMessagesKey)
    }
    
    func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            }
        }
        
        UNUserNotificationCenter.current().delegate = self
    }
    
    func startBackgroundSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { _ in
            Task {
                await self.syncMessages()
            }
        }
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.esc.gmailclient.refresh", using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    func stopBackgroundSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()
        
        Task {
            await syncMessages()
            task.setTaskCompleted(success: true)
        }
    }
    
    func scheduleAppRefresh() {
        // Background tasks don't work properly in simulator/debug mode
        // This error can be safely ignored during development
        let request = BGAppRefreshTaskRequest(identifier: "com.esc.gmailclient.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Expected error in debug/simulator - BGTaskSchedulerErrorDomain Code=3
            // means the task couldn't be scheduled (normal during debugging)
            #if DEBUG
            // Suppress this error in debug builds as it's expected
            #else
            print("Could not schedule app refresh: \(error)")
            #endif
        }
    }
    
    @MainActor
    private func syncMessages() async {
        guard AuthenticationManager.shared.isSignedIn else { return }
        
        do {
            let (messageIds, _) = try await GmailAPIService.shared.listMessages(query: "is:unread", maxResults: 10)
            
            // Clean up notified messages that are no longer unread
            notifiedMessageIds = notifiedMessageIds.intersection(messageIds)
            
            for id in messageIds {
                // Skip if we've already notified about this message
                if notifiedMessageIds.contains(id) {
                    continue
                }
                
                if let message = try? await GmailAPIService.shared.getMessage(id: id) {
                    if !message.isFromMe && !message.isRead {
                        showNotification(for: message)
                        notifiedMessageIds.insert(message.id)
                    }
                }
            }
            
            saveNotifiedMessages()
        } catch {
            print("Error syncing messages: \(error)")
        }
    }
    
    private func showNotification(for message: EmailMessage) {
        let content = UNMutableNotificationContent()
        content.title = message.from
        content.body = message.snippet
        content.sound = .default
        content.badge = NSNumber(value: notifiedMessageIds.count)
        content.userInfo = ["messageId": message.id, "threadId": message.threadId]
        
        let request = UNNotificationRequest(
            identifier: message.id,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func clearNotifiedMessage(_ messageId: String) {
        notifiedMessageIds.remove(messageId)
        saveNotifiedMessages()
        
        // Update badge count
        UNUserNotificationCenter.current().setBadgeCount(notifiedMessageIds.count)
    }
    
    func clearAllNotifiedMessages() {
        notifiedMessageIds.removeAll()
        saveNotifiedMessages()
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                               willPresent notification: UNNotification, 
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                               didReceive response: UNNotificationResponse, 
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if let threadId = userInfo["threadId"] as? String {
            NotificationCenter.default.post(
                name: Notification.Name("OpenThread"),
                object: nil,
                userInfo: ["threadId": threadId]
            )
        }
        
        completionHandler()
    }
}