# SleepyJoe (Focus) – Agent & Algorithmic Architecture (AGENTS.md)

Dieses Dokument dient als zentrale Knowledge-Base für Agenten und Entwickler zur kontinuierlichen Weiterentwicklung des Schläfrigkeits-Erkennungsmodells.

---

## 1. Physiologische Grundvoraussetzungen & Sensor-Quellen

Beim Einnicken (Übergang in Schlafstadium N1 / Mikroschlaf) verhalten sich die 3 Kernsignale wie folgt:

1. **Mikro-Jitter Varianz ($\sigma^2_{\text{jitter}}$)**: 
   - *Waches ruhiges Sitzen*: Regelmäßige Mikro-Korrekturspikes (Tippen, Atmung, Haltungskorrekturen) im Bereich $>0.015$.
   - *Einnicken*: Absolute physiologische Nulllinie ($\sigma^2_{\text{jitter}} < 0.005$) durch Muskelatonie.
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

1. **Sofortige Aufwach-Erkennung (Instant High-Energy Wake Gesture)**:
   - Bei der Aufwach-Erkennung gibt es **keine künstliche Zeitverzögerung (0 Sekunden)**. 
   - Sobald die Sensoren eine klare Aufwach-Geste erfassen (Hand schütteln $\text{movementScore} > 0.40$ oder Arm weg bewegen / Haltung wieder aufrichten), bricht der Alarm **sofort augenblicklich** ab.
   - Kleines passives Zucken ($\text{movementScore} < 0.20$) wird ignoriert, damit der Alarm sicher weckt.
2. **Refraktäre Grace Period (10 Sekunden)**:
   - Sobald die App wieder auf den Status **Aktiv (Grün)** zurückkehrt, geht das System für 10 Sekunden in eine Schutzphase, um Mehrfach-Schocks zu vermeiden.
3. **5-Sekunden Feedback-Fenster nach Aktivierung**:
   - Die Feedback-Buttons (`[ ✓ ] [ ✕ ]`) erscheinen erst beim Wechsel zurück in **Aktiv (Grün)** für 5 Sekunden.
4. **Diskrete Opt-In Logik**:
   - Wird das Feedback ignoriert, verfällt es nach 5s spurlos ohne Datenänderung.

---

## 4. Feature Engineering & ML-Backlog für spätere Offline-Analysen

Da `TelemetryLogger` die rohen 5-Sekunden-Zeitreihen ($50 \text{ Steps} \times 4 \text{ Kanäle}$) speichert, können wir später auf den gesammelten Daten folgende Feature-Muster evaluieren:

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

## 5. Machine Learning Pipeline Architecture (LSTM / CoreML)

1. **Daten-Aggregation**: Sammeln der echten 5s-JSON-Samples (`true_positive` vs. `false_positive`).
2. **Offline-Validation auf dem Mac**: Testen verschiedener Klassifikatoren (Random Forest, TCN, LSTM) bezüglich F1-Score & Precision-Recall-Curve.
3. **CoreML Export & On-Device Updating**: Konvertieren des besten Modells via `coremltools` in ein `.mlpackage` zur extrem stromsparenden Inference auf dem Apple Watch Neural Engine Chip (<1.5 ms).
