import SwiftUI

/// Streamlined Settings view with exact requested section order:
/// 1. Haptik / Intensität
/// 2. Zufalls-Pings
/// 3. Empfindlichkeit (Auto vs Manuell)
/// 4. Gelerntes Profil (Only visible when Auto-Empfindlichkeit is enabled)
struct SettingsView: View {
    @ObservedObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var useAutoSensitivity: Bool
    @State private var sensitivity: Double
    @State private var pingInterval: Int
    @State private var hapticStrength: HapticStrength
    @State private var enablePings: Bool
    @State private var showResetConfirmation = false
    
    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        let s = sessionManager.settings
        _useAutoSensitivity = State(initialValue: s.useAutoSensitivity)
        _sensitivity = State(initialValue: Double(s.sensitivity))
        _pingInterval = State(initialValue: s.pingIntervalMinutes)
        _hapticStrength = State(initialValue: s.hapticStrength)
        _enablePings = State(initialValue: s.enableRandomPings)
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 1. Haptic Intensity (Top)
                Section("Haptic Intensity") {
                    Picker("Strength", selection: $hapticStrength) {
                        ForEach(HapticStrength.allCases) { strength in
                            Text(strength.label).tag(strength)
                        }
                    }
                }
                
                // 2. Random Pings
                Section("Random Pings") {
                    Toggle("Enabled", isOn: $enablePings)
                    
                    if enablePings {
                        Picker("Interval", selection: $pingInterval) {
                            Text("1 min").tag(1)
                            Text("5 min").tag(5)
                            Text("10 min").tag(10)
                            Text("15 min").tag(15)
                            Text("20 min").tag(20)
                        }
                    }
                }
                
                // 3. Sensitivity (Auto vs Manual)
                Section("Sensitivity") {
                    Toggle("Auto (Learned)", isOn: $useAutoSensitivity)
                    
                    if !useAutoSensitivity {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Level")
                                Spacer()
                                Text("\(Int(sensitivity))")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $sensitivity, in: 1...5, step: 1)
                        }
                    }
                }
                
                // 4. Learned Profile (Only visible if Auto-Sensitivity is active)
                if useAutoSensitivity {
                    Section("Learned Profile") {
                        HStack {
                            Text("Precision")
                            Spacer()
                            Text("\(sessionManager.adaptiveEngine.precisionPercentage)%")
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Calibration")
                            Spacer()
                            Text(String(format: "%+.1fs", sessionManager.adaptiveEngine.personalStillnessOffset))
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Saved Samples")
                            Spacer()
                            Text("\(sessionManager.telemetryLogger.totalSavedSamples)")
                                .foregroundStyle(.secondary)
                        }
                        
                        Button("Reset Calibration") {
                            showResetConfirmation = true
                        }
                        .foregroundStyle(.red.opacity(0.8))
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        saveAndDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
            }
            .confirmationDialog(
                "Reset Calibration?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset All Learning", role: .destructive) {
                    sessionManager.resetAllLearning()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All personalized model weights and training samples will be permanently cleared.")
            }
            .onChange(of: useAutoSensitivity) { _, _ in applySettings() }
            .onChange(of: sensitivity) { _, _ in applySettings() }
            .onChange(of: pingInterval) { _, _ in applySettings() }
            .onChange(of: hapticStrength) { _, newStrength in
                applySettings()
                sessionManager.hapticManager.playSample(for: newStrength)
            }
            .onChange(of: enablePings) { _, _ in applySettings() }
        }
    }
    
    private func applySettings() {
        var newSettings = sessionManager.settings
        newSettings.useAutoSensitivity = useAutoSensitivity
        newSettings.sensitivity = Int(sensitivity)
        newSettings.pingIntervalMinutes = pingInterval
        newSettings.hapticStrength = hapticStrength
        newSettings.enableRandomPings = enablePings
        sessionManager.updateSettings(newSettings)
    }
    
    private func saveAndDismiss() {
        applySettings()
        dismiss()
    }
}

#Preview {
    SettingsView(sessionManager: SessionManager())
}
