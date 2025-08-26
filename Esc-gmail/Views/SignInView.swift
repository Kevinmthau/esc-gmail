import SwiftUI
import GoogleSignInSwift

struct SignInView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("ESC Gmail Client")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Sign in to access your Gmail messages")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            GoogleSignInButton(scheme: .dark, style: .wide, state: .normal) {
                authManager.signIn()
            }
            .frame(height: 55)
            .padding(.horizontal, 40)
            
            Text("Your Gmail data is secure and only accessible by you")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    SignInView()
        .environmentObject(AuthenticationManager.shared)
}