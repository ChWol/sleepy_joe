import SwiftUI

/// Main entry view – icon-driven native watchOS interface.
struct ContentView: View {
    @StateObject private var sessionManager = SessionManager()
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if sessionManager.state != .idle {
                SessionView(sessionManager: sessionManager)
                    .ignoresSafeArea()
            } else {
                NavigationStack {
                    startScreen
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(sessionManager: sessionManager)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    
    // MARK: - Icon-Driven Start Screen
    
    private var startScreen: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Focus")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                
                Spacer()
                
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
            
            Spacer()
            
            // Icon-Driven Circular Start Button
            Button {
                sessionManager.startSession()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 72, height: 72)
                    
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 72, height: 72)
                    
                    Image(systemName: "play.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                        .offset(x: 2)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.horizontal, 4)
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    ContentView()
}
