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
                // 1. Haptik / Intensität (Top)
                Section("Intensität (Haptik)") {
                    Picker("Stärke", selection: $hapticStrength) {
                        ForEach(HapticStrength.allCases) { strength in
                            Text(strength.label).tag(strength)
                        }
                    }
                }
                
                // 2. Zufalls-Pings
                Section("Zufalls-Pings") {
                    Toggle("Aktiv", isOn: $enablePings)
                    
                    if enablePings {
                        Picker("Intervall", selection: $pingInterval) {
                            Text("1 Min").tag(1)
                            Text("5 Min").tag(5)
                            Text("10 Min").tag(10)
                            Text("15 Min").tag(15)
                            Text("20 Min").tag(20)
                        }
                    }
                }
                
                // 3. Empfindlichkeit (Auto vs Manuell)
                Section("Empfindlichkeit") {
                    Toggle("Auto (Gelernt)", isOn: $useAutoSensitivity)
                    
                    if !useAutoSensitivity {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Stufe")
                                Spacer()
                                Text("\(Int(sensitivity))")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $sensitivity, in: 1...5, step: 1)
                        }
                    }
                }
                
                // 4. Gelerntes Profil (Only visible if Auto-Sensitivity is active)
                if useAutoSensitivity {
                    Section("Gelerntes Profil") {
                        HStack {
                            Text("Genauigkeit")
                            Spacer()
                            Text("\(sessionManager.adaptiveEngine.precisionPercentage)%")
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Anpassung")
                            Spacer()
                            Text(String(format: "%+.1fs", sessionManager.adaptiveEngine.personalStillnessOffset))
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Datensätze")
                            Spacer()
                            Text("\(sessionManager.telemetryLogger.totalSavedSamples)")
                                .foregroundStyle(.secondary)
                        }
                        
                        Button("Lernen zurücksetzen") {
                            showResetConfirmation = true
                        }
                        .foregroundStyle(.red.opacity(0.8))
                    }
                }
            }
            .navigationTitle("Optionen")
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
                "Lernen zurücksetzen?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Wirklich zurücksetzen", role: .destructive) {
                    sessionManager.adaptiveEngine.resetCalibration()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Alle gelernten Anpassungen und Treffer-Daten werden unwiderruflich gelöscht.")
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
