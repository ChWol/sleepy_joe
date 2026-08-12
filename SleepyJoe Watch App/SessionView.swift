import SwiftUI

/// Active session view – native standalone watch face with discreet feedback.
/// Completely quiet UI without bright red alerts to remain 100% subtle in meetings.
struct SessionView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var isPulsing = false
    @State private var feedbackAnimationColor: Color? = nil
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Top Right Discreet 'X' Dismissal Button - Aligned exactly with ContentView header
            VStack {
                HStack {
                    Spacer()
                    Button {
                        sessionManager.stopSession()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .padding(.trailing, 6)
                }
                Spacer()
            }
            
            // Center: Minimalist Ambient Status Gauge (Subtle & Quiet)
            VStack(spacing: 12) {
                ZStack {
                    // Outer subtle breathing ring
                    Circle()
                        .stroke(statusColor.opacity(0.25), lineWidth: 2)
                        .frame(width: 64, height: 64)
                        .scaleEffect(isPulsing ? 1.15 : 1.0)
                        .opacity(isPulsing ? 0.3 : 0.7)
                    
                    // Inner ring
                    Circle()
                        .stroke(statusColor.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 48, height: 48)
                    
                    // Center status dot (flashes feedback micro-pulse on tap)
                    Circle()
                        .fill(feedbackAnimationColor ?? statusColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(feedbackAnimationColor != nil ? 1.8 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: feedbackAnimationColor)
                }
                
                // Always subtle, neutral text - no loud bright red alert banners!
                Text("Focus Active")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            
            // Bottom: Live Discreet Feedback Buttons (Appears for 6s after an Alert)
            if sessionManager.showFeedbackPrompt {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 16) {
                        // True Positive (✓ Echtes Einnicken)
                        Button {
                            triggerFeedbackAnimation(color: .green)
                            sessionManager.submitFeedback(wasTruePositive: true)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                        
                        // False Positive (✕ Fehlalarm)
                        Button {
                            triggerFeedbackAnimation(color: .orange)
                            sessionManager.submitFeedback(wasTruePositive: false)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 6)
                    .transition(.opacity)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
    
    private var statusColor: Color {
        switch sessionManager.state {
        case .idle: return .gray
        case .monitoring: return .green.opacity(0.7)
        case .warning: return .orange.opacity(0.8)
        case .alerting: return .orange // Subtle orange pulse during alert - no harsh red!
        }
    }
    
    private func triggerFeedbackAnimation(color: Color) {
        feedbackAnimationColor = color
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                feedbackAnimationColor = nil
            }
        }
    }
}

#Preview {
    SessionView(sessionManager: SessionManager())
}
