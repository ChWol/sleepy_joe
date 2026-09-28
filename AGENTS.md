# SleepyJoe (Focus) – Agent & Algorithmic Architecture (AGENTS.md)

Dieses Dokument dient als zentrale Knowledge-Base für Agenten und Entwickler zur kontinuierlichen Weiterentwicklung des Schläfrigkeits-Erkennungsmodells.

---

## 1. Sensor-Hypothesen und Grenzen

Die folgenden Zahlen sind heuristische Startwerte, keine physiologischen Grenzwerte. Insbesondere ist absolute Muskelatonie kein verlässliches Kennzeichen von N1; sie wird vor allem mit REM-Schlaf verbunden. Handgelenks-Aktigraphie verwechselt ruhiges Wachsein häufig mit Schlaf ([Validierungsstudie gegen Polysomnographie](https://pmc.ncbi.nlm.nih.gov/articles/PMC3792393/)). Das Produkt soll als Aufmerksamkeitshilfe verstanden und anhand echter Nutzung kalibriert werden.

Beim Einnicken (Übergang in Schlafstadium N1 / Mikroschlaf) verhalten sich die 3 Kernsignale wie folgt:

1. **Mikro-Jitter Varianz ($\sigma^2_{\text{jitter}}$)**: 
   - *Waches ruhiges Sitzen*: Regelmäßige Mikro-Korrekturspikes (Tippen, Atmung, Haltungskorrekturen) im Bereich $>0.015$.
   - *Mögliches Einnicken*: Eine Phase geringerer Bewegung kann auftreten, ist allein aber nicht spezifisch für Schlaf.
2. **Handgelenks-Pitch ($\theta_{\text{pitch}}$)**:
   - *Waches Sitzen*: Muskeltonus hält die Ausrichtung.
   - *Einnicken*: Absacken nach unten ($\Delta \theta > 10^\circ$) oder statische Abwärtsneigung ($<-15^\circ$).
3. **Herzfrequenz-Trend ($\Delta \text{HR}$)**:
   - *Einnicken*: Relative Verringerung um $4\%$ bis $12\%$ gegenüber der Sitz-Baseline.

---

## 2. Daten-Imbalance & Skewness (Herausforderung in der Praxis)

### Das Problem:
In der echten Nutzung gibt es ein starkes Klassen-Ungleichgewicht:
- **$>95\%$ Falsche Alarme / Waches Sitzen (Negative Samples)**
- **$<5\%$ Echtes Einnicken (Positive Samples)**

### Strategie gegen Data Skewness:
- Naive statistische Anpassungen würden bei vielen False Positives den Timer unendlich nach oben schieben (z. B. auf 15 Sekunden). Dadurch würde die App beim echten Einnicken **viel zu spät** reagieren.
- **Asymmetrisches Feature-Weighting**:
  - Ein `✕` (Fehlalarm) erhöht **nicht** endlos die Zeitdauer, sondern verfeinert den **Mikro-Jitter Schwellenwert ($\epsilon_{\text{jitter}}$)** und bestraft unzuverlässige Einzel-Sensoren (z. B. rauschigen Puls).
  - Ein `✓` (Echtes Einnicken) hat ein hohes Gewicht und schärft die Ansprechzeit sofort nach.

---

## 3. Implementierte UX & System-Regeln

1. **Endlos-Alarm bis zur bewussten Aufwach-Aktion (Continuous Looping Alarm)**:
   - Der Alarm vibriert **kontinuierlich und endlos** weiter (kein künstlicher 5.5s-Auto-Timeout), bis der Nutzer entweder:
     a) Eine klare, bewusste Aufwach-Geste ausführt (Hand schütteln $\text{movementScore} > 0.40$ oder Arm aufrichten $\text{movementScore} > 0.20$), ODER
     b) Direkt auf einen der Feedback-Buttons (`[ ✓ ]` oder `[ ✕ ]`) tippt.
   - Kleines passives Zucken ($\text{movementScore} < 0.20$) wird ignoriert, damit der Alarm sicher weckt.
   - Die App beendet die Haptik beim nächsten passenden Sensorereignis ohne zusätzlichen Polling-Timer; eine physisch garantierte Null-Latenz ist nicht möglich.
2. **Sofortige Button-Anzeige beim Alarm (Instant Feedback Buttons)**:
   - Die Feedback-Buttons (`[ ✓ ] [ ✕ ]`) werden mit dem Alarmzustand gesetzt und bleiben nach dem Aufwachen für 5 Sekunden sichtbar.
3. **Refraktäre Grace Period (10 Sekunden)**:
   - Sobald die App wieder auf den Status **Aktiv (Grün)** zurückkehrt, geht das System für 10 Sekunden in eine Schutzphase, um Mehrfach-Schocks zu vermeiden.
4. **Diskrete Opt-In Logik**:
   - Wird das Feedback nach dem Aufwachen 5s ignoriert, verfällt es spurlos ohne Datenänderung.

---

## 4. Feature Engineering & ML-Backlog für spätere Offline-Analysen

Da `TelemetryLogger` das Alarmfenster (bis zu $50 \text{ Steps}$ mit Pitch, Bewegungsdelta und drei Beschleunigungsachsen) speichert, können wir später auf den gesammelten Daten folgende Feature-Muster evaluieren:

### A. Zeitbereich-Features (Time-Domain)
1. **Signal-Spanne (Peak-to-Peak Amplitude)**: $\text{Spanne} = \max(x) - \min(x)$. Erkennt schlagartiges Hand-Schütteln oder Arm-Rucken sofort.
2. **Signal Magnitude Area (SMA)**: $\frac{1}{N} \sum (|x| + |y| + |z|)$. Erfasst die absolute kinetische Gesamtenergie.
3. **Varianz & Standardabweichung ($\sigma^2$)**: Unterscheidet bewussten Muskeltonus von absoluter Muskelatonie beim Einnicken.

### B. Frequenzbereich-Features (Frequency-Domain / Fourier-Transformation)
1. **Fast Fourier Transform (FFT) Power Spectral Density (PSD)**:
   - *Waches Zuhören*: Zeigt charakteristische hochfrequente Korrektur-Spikes ($>3\text{ Hz}$).
   - *Einnicken*: Zeigt ein vollständiges Einknicken höherer Frequenzbänder (Energie nur bei $<0.5\text{ Hz}$).
2. **Spectral Entropy & Centroid**: Misst den Rauschanteil vs. statische Abwärtsneigung.

### C. Winkelgeschwindigkeit & Haltungs-Vektoren
1. **Pitch-Winkelgeschwindigkeit ($\frac{d\theta}{dt}$)**: Erfasst die Geschwindigkeit des Absackens vs. schnelles Aufrichten des Arms.

---

## 5. Experimentelle On-Device ML Pipeline (CoreML Updatable MLP)

**Stand September 2026:** Der CoreML-Pfad bleibt als Experiment im Repository, wird aber in der laufenden Erkennung weder geladen noch trainiert. Die initialen Gewichte sind zufällig und die synthetischen Anchor-Samples sind keine validierten Schlafdaten. Eine direkte Alarm- oder Veto-Entscheidung daraus wäre bei wenigen echten Positivbeispielen unzuverlässig. Produktiv arbeitet die Regel-Engine mit konservativem Abgleich explizit gelabelter Fehlalarme; bestätigtes Einnicken schützt ein ähnliches Muster vor einem Veto. Eine Aktivierung des MLP erfordert unabhängige Validierung auf echten, personenbezogen getrennten Zeitreihen.

### A. Modell-Architektur
- **Typ**: Updatable 2-Layer MLP (Multi-Layer Perceptron)
- **Struktur**: Input(16) → Dense(16, ReLU) → Dense(2, Softmax)
- **Parameter**: ~306 (fc1: 272 frozen, fc2: 34 updatable)
- **Modellgröße**: < 50 KB (.mlmodelc)
- **Inferenz-Latenz**: < 0.2 ms (Apple Neural Engine + CPU)
- **Trainingszeit auf dem Gerät**: ~20 ms (15 Epochen)
- **Klassen**: `["awake", "sleep"]`

### B. 16-Feature-Vektor (vDSP-Extraktion aus 5s-Fenster)

| # | Feature | Formel | Physiologische Bedeutung |
|---|---------|--------|--------------------------|
| 0–2 | Mean X/Y/Z | $\bar{x}, \bar{y}, \bar{z}$ | Schwerkraft-Orientierung |
| 3–5 | Varianz X/Y/Z | $\sigma^2$ | **Mikro-Jitter vs. Muskelatonie** |
| 6 | Total Jitter Varianz | $\frac{\sigma^2_x + \sigma^2_y + \sigma^2_z}{3}$ | **Kern-Schlafindikator** |
| 7 | Signal Magnitude Area | $\frac{1}{N}\sum(\|x\|+\|y\|+\|z\|)$ | Kinetische Gesamtenergie |
| 8–10 | Peak-to-Peak X/Y/Z | $\max - \min$ | Handschütteln / Arm-Ruck |
| 11 | Mean Pitch | $\bar{\theta}$ | Durchschn. Handgelenkswinkel |
| 12 | Pitch Delta | $\theta_{50} - \theta_{1}$ | **Arm-Absacken** |
| 13 | Pitch Varianz | $\sigma^2_\theta$ | Haltungsstabilität |
| 14 | Zero Crossing Rate | $\frac{\text{ZCR}}{N}$ | Frequenz-Proxy (bewusstes Zucken) |
| 15 | Peak Energy | $\max(x)^2 + \max(y)^2 + \max(z)^2$ | Burst-Energie |

### C. Anti-Catastrophic-Forgetting: Anchor-Samples
- **20 synthetische Prototyp-Samples** im App-Bundle (`anchor_samples.json`); kein validierter Goldstandard
- 10 × "awake" (realistische Mikro-Korrekturen), 10 × "sleep" (Muskelatonie)
- Bei jedem Training: $\text{Batch} = \text{Anchors (20)} + \text{User-Buffer (bis 100)}$
- "sleep"-Samples werden ×3 dupliziert gegen Klassen-Ungleichgewicht

### D. Historisch vorgesehene Training-Trigger (derzeit deaktiviert)
1. **Foreground**: Bei jedem `✓`/`✕` Tap → 15 Epochen (`.utility` QoS)
2. **Konsolidierung**: `WKApplicationRefreshBackgroundTask` wenn Uhr lädt & Akku > 50% → 50 Epochen
3. **Replay-Buffer**: Ring-Buffer mit max. 100 gelabelten Feature-Vektoren auf Disk

### E. Historisches Ensemble-Konzept (derzeit deaktiviert)
$$\text{totalConfidence} = \max(\text{ruleConfidence}, \text{mlConfidence})$$
- Alarm wird ausgelöst, wenn **entweder** Rule-Engine **oder** ML-Modell den Schwellenwert überschreitet
- Graceful Degradation: ML-Modell ist optional; Rule-Engine funktioniert immer als Fallback

### F. Zukünftige Verbesserungen
1. **Offline-Validation auf dem Mac**: Random Forest, TCN, LSTM auf gesammelten Telemetrie-Daten benchmarken
2. **iPhone-Companion-Offloading**: Telemetrie via `WCSession.transferFile()` an iPhone für tiefere Analyse
3. **Frequenz-Features (FFT)**: PSD-Bänder als zusätzliche Features für v2 des Feature-Vektors

---

## 6. Aktueller Produktpfad und Validierung

- Ein Alarm benötigt frische Bewegungsdaten, Stillstand und entweder eine aktuelle Haltungsänderung, einen frischen Puls-Trend oder ungewöhnlich lange, sehr ruhige Bewegungslosigkeit. Statische Handgelenksneigung allein ist kein Schlafbeweis.
- Nach drei ähnlichen, ausdrücklich gemeldeten Fehlalarmen wird nur der mehrdeutige Stillstands-/Puls-Pfad unterdrückt. Eine Haltungsänderung bleibt aktiv. Ein ähnliches bestätigtes Einnicken hebt das Veto auf.
- Feedback beschriftet das beim Alarm eingefrorene Sensorfenster. Bewegungen beim Aufwachen gelangen nicht in dieses Trainingsbeispiel. Ohne vollständiges 5-Sekunden-Fenster wird kein persönliches Muster gespeichert.
- Der Alarm endet beim passenden Sensorereignis oder Feedback-Tap; die physische Reaktionszeit der Uhr ist nicht null. Danach gelten zehn Sekunden Schutzphase und fünf Sekunden optionale Feedback-Anzeige.
- Feature 6 ist der Mittelwert der drei Achsen-Varianzen. Ältere Pufferdaten enthalten dort den früheren Quadrierungsfehler; der produktive Mustervergleich nutzt dieses Feld nicht.
- Die Schwellenwerte und Musterabstände sind Startwerte, keine medizinisch validierte Schlafdiagnose. Vor einer Veröffentlichung sind Tests auf echten Uhren mit ruhiger Arbeit, verschiedenen Armhaltungen, fehlendem Puls, echten Einnickereignissen, Akkulaufzeit und Hintergrundverhalten erforderlich.
