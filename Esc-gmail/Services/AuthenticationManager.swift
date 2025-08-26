import Foundation
import GoogleSignIn

class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isSignedIn = false
    @Published var userEmail: String?
    @Published var accessToken: String?
    
    private let clientID = "999923476073-b4m4r3o96gv30rqmo71qo210oa46au74.apps.googleusercontent.com"
    
    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }
    
    func signIn() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: nil,
            additionalScopes: ["https://www.googleapis.com/auth/gmail.modify"]
        ) { [weak self] result, error in
            if let user = result?.user {
                self?.signIn(user: user)
            }
        }
    }
    
    func signIn(user: GIDGoogleUser) {
        self.isSignedIn = true
        self.userEmail = user.profile?.email
        
        user.refreshTokensIfNeeded { [weak self] user, error in
            guard let user = user, error == nil else { return }
            self?.accessToken = user.accessToken.tokenString
        }
    }
    
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        userEmail = nil
        accessToken = nil
    }
    
    func refreshTokenIfNeeded(completion: @escaping (String?) -> Void) {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            completion(nil)
            return
        }
        
        currentUser.refreshTokensIfNeeded { user, error in
            guard let user = user, error == nil else {
                completion(nil)
                return
            }
            self.accessToken = user.accessToken.tokenString
            completion(user.accessToken.tokenString)
        }
    }
}