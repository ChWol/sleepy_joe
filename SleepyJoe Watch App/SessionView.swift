import SwiftUI

/// Active session view – native standalone watch face.
/// Header layout is 100% identical to ContentView so gearshape and xmark icons match pixel-for-pixel.
struct SessionView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var isPulsing = false
    @State private var feedbackAnimationColor: Color? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header: Identical bounds, padding, and font size as ContentView's gear icon
            HStack {
                Spacer()
                
                Button {
                    sessionManager.stopSession()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
            
            Spacer()
            
            // Center: Minimalist Ambient Status Gauge
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(statusColor.opacity(0.25), lineWidth: 2)
                        .frame(width: 60, height: 60)
                        .scaleEffect(isPulsing ? 1.15 : 1.0)
                        .opacity(isPulsing ? 0.3 : 0.7)
                    
                    Circle()
                        .stroke(statusColor.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                    
                    Circle()
                        .fill(feedbackAnimationColor ?? statusColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(feedbackAnimationColor != nil ? 1.8 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: feedbackAnimationColor)
                }
                
                Text(sessionManager.isGracePeriodActive ? "Grace Period" : "Focus Active")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            
            Spacer()
            
            // Bottom: Live Discreet Feedback Bar (Only shown if Auto-Sensitivity is active)
            if sessionManager.showFeedbackPrompt && sessionManager.settings.useAutoSensitivity {
                HStack(spacing: 18) {
                    // True Positive (✓ Echtes Einnicken)
                    Button {
                        triggerFeedbackAnimation(color: .green)
                        sessionManager.submitFeedback(wasTruePositive: true)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    
                    // False Positive (✕ Fehlalarm)
                    Button {
                        triggerFeedbackAnimation(color: .orange)
                        sessionManager.submitFeedback(wasTruePositive: false)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
    
    private var statusColor: Color {
        if sessionManager.isGracePeriodActive {
            return .blue.opacity(0.6)
        }
        switch sessionManager.state {
        case .idle: return .gray
        case .monitoring: return .green.opacity(0.7)
        case .warning: return .orange.opacity(0.8)
        case .alerting: return .orange
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
