//
//  escchatmailApp.swift
//  escchatmail
//
//  Created by Kevin Thau on 8/24/25.
//

import SwiftUI
import GoogleSignIn
import BackgroundTasks

@main
struct escchatmailApp: App {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var notificationService = NotificationService.shared
    
    init() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.esc.gmailclient.refresh",
            using: nil
        ) { task in
            NotificationService.shared.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ConversationListView()
                .environmentObject(authManager)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onAppear {
                    GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                        if let user = user {
                            authManager.signIn(user: user)
                            notificationService.startBackgroundSync()
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    notificationService.scheduleAppRefresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    if authManager.isSignedIn {
                        notificationService.startBackgroundSync()
                    }
                }
        }
    }
}
