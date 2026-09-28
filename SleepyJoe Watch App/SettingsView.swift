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
    @State private var showDeleteDataConfirmation = false
    @State private var saveDiagnostics: Bool
    
    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        let s = sessionManager.settings
        _useAutoSensitivity = State(initialValue: s.useAutoSensitivity)
        _sensitivity = State(initialValue: Double(s.sensitivity))
        _pingInterval = State(initialValue: s.pingIntervalMinutes)
        _hapticStrength = State(initialValue: s.hapticStrength)
        _enablePings = State(initialValue: s.enableRandomPings)
        _saveDiagnostics = State(initialValue: sessionManager.telemetryLogger.diagnosticsEnabled)
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
                    Toggle("Adapt to feedback", isOn: $useAutoSensitivity)
                    
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
                        Text("Explicit feedback adjusts personal patterns. These heuristics are not a sleep diagnosis.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("Confirmed alerts")
                            Spacer()
                            Text("\(sessionManager.adaptiveEngine.truePositivesCount)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("False alarms")
                            Spacer()
                            Text("\(sessionManager.adaptiveEngine.falsePositivesCount)")
                                .foregroundStyle(.secondary)
                        }
                        
                        Button("Reset all learning") {
                            showResetConfirmation = true
                        }
                        .foregroundStyle(.red.opacity(0.8))
                    }
                }

                Section("Your Data") {
                    Text("Focus is an attention aid. Wrist motion and heart rate can suggest drowsiness, but cannot confirm sleep.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Sensor windows are saved on this watch when you submit alert feedback or log a missed event. They help recognize similar personal patterns and are capped at 1,000 windows.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("Save decision diagnostics", isOn: $saveDiagnostics)
                    Text("When enabled, Focus keeps timestamps, reasons, and thresholds on this watch. It does not include raw motion samples.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("Saved windows")
                        Spacer()
                        Text("\(sessionManager.telemetryLogger.totalSavedSamples)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Diagnostic events")
                        Spacer()
                        Text("\(sessionManager.telemetryLogger.totalDecisionTraceEntries)")
                            .foregroundStyle(.secondary)
                    }
                    Button("Delete saved sensor data", role: .destructive) {
                        showDeleteDataConfirmation = true
                    }
                    .disabled(sessionManager.telemetryLogger.totalSavedSamples == 0 && sessionManager.mlReplayBuffer.entries.isEmpty && sessionManager.telemetryLogger.totalDecisionTraceEntries == 0)
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
                "Reset learning?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Learning", role: .destructive) {
                    sessionManager.resetAllLearning()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All learned calibration and saved personal sensor examples will be cleared.")
            }
            .confirmationDialog(
                "Delete saved sensor data?",
                isPresented: $showDeleteDataConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Sensor Data", role: .destructive) {
                    sessionManager.deleteStoredSensorData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saved alert windows, personal example patterns, and diagnostic events will be removed. Your sensitivity settings and feedback counts will remain.")
            }
            .onChange(of: useAutoSensitivity) { _, _ in applySettings() }
            .onChange(of: sensitivity) { _, _ in applySettings() }
            .onChange(of: pingInterval) { _, _ in applySettings() }
            .onChange(of: hapticStrength) { _, newStrength in
                applySettings()
                sessionManager.hapticManager.playSample(for: newStrength)
            }
            .onChange(of: enablePings) { _, _ in applySettings() }
            .onChange(of: saveDiagnostics) { _, enabled in
                sessionManager.telemetryLogger.setDiagnosticsEnabled(enabled)
            }
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
