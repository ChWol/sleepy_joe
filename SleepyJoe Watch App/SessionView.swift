import SwiftUI

/// Quiet, ambient active-session view.
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
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("End focus session")
                    .padding(.top, 34)
                    .padding(.trailing, 10)
                }
                Spacer()
            }
            
            // Center: ambient status with a discreet long-press action.
            VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(statusColor.opacity(0.25), lineWidth: 2)
                            .frame(width: 62, height: 62)
                            .scaleEffect(isPulsing ? 1.15 : 1.0)
                            .opacity(isPulsing ? 0.3 : 0.7)
                        
                        Circle()
                            .stroke(statusColor.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 44, height: 44)
                        
                        if sessionManager.manualLogConfirmed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Circle()
                                .fill(feedbackAnimationColor ?? statusColor)
                                .frame(width: 8, height: 8)
                                .scaleEffect(feedbackAnimationColor != nil ? 1.8 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: feedbackAnimationColor)
                        }
                    }
                    .contentShape(Circle())
                    
                    Text(statusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(sessionManager.manualLogConfirmed ? .green : (sessionManager.state == .alerting ? .orange : .white.opacity(0.68)))
                    if sessionManager.hasCheckedHealthKitAuthorization && !sessionManager.isHeartRateAvailable && sessionManager.state != .alerting {
                        Text("Motion only")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.8).onEnded { _ in
                guard sessionManager.state == .monitoring || sessionManager.state == .warning else { return }
                if sessionManager.logManualSleepOnset() {
                    triggerFeedbackAnimation(color: .green)
                }
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Focus status")
            .accessibilityValue(statusText)
            .accessibilityHint("Long press to record a missed event")
            .accessibilityAction(named: Text("Log a missed event")) {
                guard sessionManager.state == .monitoring || sessionManager.state == .warning else { return }
                if sessionManager.logManualSleepOnset() {
                    triggerFeedbackAnimation(color: .green)
                }
            }
            
            // Bottom: Live Discreet Feedback Bar (Shown immediately upon alerting AND during feedback window)
            if sessionManager.showFeedbackPrompt || sessionManager.state == .alerting {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 20) {
                        // True Positive (✓ Echtes Einnicken)
                        Button {
                            triggerFeedbackAnimation(color: .green)
                            sessionManager.submitFeedback(wasTruePositive: true)
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: 38, height: 38)
                                    .background(Color.white.opacity(0.18), in: Circle())
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Correct alert")
                        
                        // False Positive (✕ Fehlalarm)
                        Button {
                            triggerFeedbackAnimation(color: .orange)
                            sessionManager.submitFeedback(wasTruePositive: false)
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: 38, height: 38)
                                    .background(Color.white.opacity(0.18), in: Circle())
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("False alarm")
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
        if sessionManager.manualLogConfirmed {
            return "Saved"
        }
        if sessionManager.state == .alerting {
            return "Check in"
        }
        if sessionManager.isGracePeriodActive {
            return "Focus Active"
        }
        if sessionManager.settings.enableMotionDetection && !sessionManager.isMotionAvailable {
            return "Motion unavailable"
        }
        if sessionManager.state == .warning {
            return "Checking..."
        }
        return "Focus Active"
    }
    
    private var statusColor: Color {
        if sessionManager.manualLogConfirmed {
            return .green
        }
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
