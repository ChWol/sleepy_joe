import SwiftUI

/// Active session view – native standalone watch face.
/// Restored to original ZStack layout with xmark placed neatly under the top status bar (padding top 34).
struct SessionView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var isPulsing = false
    @State private var feedbackAnimationColor: Color? = nil
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Top Right Discreet 'X' Dismissal Button (Originally top 28, now slightly further down at top 34)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        sessionManager.stopSession()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 34)
                    .padding(.trailing, 10)
                }
                Spacer()
            }
            
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
                
                Text(statusText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(sessionManager.state == .alerting ? .orange : .white.opacity(0.4))
            }
            
            // Bottom: Live Discreet Feedback Bar (Shown immediately upon alerting AND during feedback window)
            if (sessionManager.showFeedbackPrompt || sessionManager.state == .alerting) && sessionManager.settings.useAutoSensitivity {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 20) {
                        // True Positive (✓ Echtes Einnicken)
                        Button {
                            triggerFeedbackAnimation(color: .green)
                            sessionManager.submitFeedback(wasTruePositive: true)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.18), in: Circle())
                        }
                        .buttonStyle(.plain)
                        
                        // False Positive (✕ Fehlalarm)
                        Button {
                            triggerFeedbackAnimation(color: .orange)
                            sessionManager.submitFeedback(wasTruePositive: false)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.18), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
    
    private var statusText: String {
        if sessionManager.state == .alerting {
            return "Einnicken erkannt"
        }
        if sessionManager.isGracePeriodActive {
            return "Grace Period"
        }
        if sessionManager.state == .warning {
            return "Prüfe..."
        }
        return "Focus Active"
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
