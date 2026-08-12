import SwiftUI

/// Active session view – native standalone watch face.
/// Includes discreet 6-second live feedback bar (✓/✕) when alerts trigger.
struct SessionView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Top Right Discreet 'X' Dismissal Button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        sessionManager.stopSession()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 28)
                    .padding(.trailing, 10)
                }
                Spacer()
            }
            
            // Center: Minimalist Ambient Status Gauge
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(statusColor.opacity(0.25), lineWidth: 2)
                        .frame(width: 64, height: 64)
                        .scaleEffect(isPulsing ? 1.15 : 1.0)
                        .opacity(isPulsing ? 0.3 : 0.7)
                    
                    Circle()
                        .stroke(statusColor.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 48, height: 48)
                    
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }
                
                Text(sessionManager.state == .alerting ? "Alert!" : "Focus Active")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(sessionManager.state == .alerting ? .red : .white.opacity(0.5))
            }
            
            // Bottom: Live Discreet Feedback Bar (Appears for 6s after an Alert)
            if sessionManager.showFeedbackPrompt {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 12) {
                        // True Positive (✓ Echtes Einnicken)
                        Button {
                            withAnimation {
                                sessionManager.submitFeedback(wasTruePositive: true)
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Echt")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.2), in: Capsule())
                            .overlay(Capsule().stroke(Color.green.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        
                        // False Positive (✕ Fehlalarm)
                        Button {
                            withAnimation {
                                sessionManager.submitFeedback(wasTruePositive: false)
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Fehler")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .overlay(Capsule().stroke(Color.orange.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
        case .monitoring: return .green.opacity(0.8)
        case .warning: return .orange
        case .alerting: return .red
        }
    }
}

#Preview {
    SessionView(sessionManager: SessionManager())
}
