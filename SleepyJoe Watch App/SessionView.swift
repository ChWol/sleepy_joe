import SwiftUI

/// Active session view – minimalist native watchOS ambient glance.
/// Harmonizes with watchOS 10 system status bar clock (no duplicate centered time).
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
                    .padding(.top, 28) // Placed neatly under system time area
                    .padding(.trailing, 10)
                }
                Spacer()
            }
            
            // Center: Minimalist Ambient Status Gauge (Complements top-right system clock)
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
                    
                    // Center status dot
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }
                
                Text("Focus Active")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
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
