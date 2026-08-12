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

1. **Refraktäre Grace Period (60 Sekunden)**:
   - Nach jedem Alarm oder Feedback-Tap geht das System für 60s in eine Schutzphase. Da der Nutzer gerade aktiv reagiert hat, sind neue Alarme für 60s gesperrt.
2. **Verlängertes Feedback-Fenster (25 Sekunden)**:
   - Die Feedback-Buttons (`[ ✓ ] [ ✕ ]`) bleiben 25s lang dezent verfügbar, damit der Nutzer genügend Zeit hat, den Arm zu heben und zu labeln – selbst wenn die Vibration längst aufgehört hat.
3. **Sofortiger Vibrations-Stopp bei Label-Tap**:
   - Sobald `✓` oder `✕` angetippt werden, bricht `hapticManager.stopCurrentSequence()` die Vibration Augenblicklich ab.
4. **Diskrete Opt-In Logik**:
   - Wird das Feedback ignoriert, verfällt es spurlos ohne Datenänderung.

---

## 4. Algorithmus- & Machine-Learning Backlog

### Idee A: Multi-Variate Time-Series Windowing & Retroaktives Labeling
- Bei 10 Hz Abtastrate entspricht ein 15-Sekunden-Fenster vor dem Alarm einer Matrix $X \in \mathbb{R}^{150 \times 4}$ ($x, y, z, \text{pitch}$).
- Wird ein Alarm mit `✓` oder `✕` gelabelt, speichert die App rückwirkend exakt dieses 150-Step Zeitfenster als gelabeltes Trainings-Sample.

### Idee B: Lightweight On-Device LSTM / TCN (CoreML)
- **Modell-Typ**: On-Device Long Short-Term Memory (LSTM) oder Temporal Convolutional Network (TCN).
- **Vorteil**: Ein LSTM erlernt zeitliche Abfolgen (z. B. *Pitch-Drop $\rightarrow$ Jitter-Drop $\rightarrow$ HR-Abfall*) weitaus präziser als statische Regel-Engines.
- **Machbarkeit**: Ein kompaktes, quantisiertes CoreML LSTM-Modell kann auf Apple Watch Prozessoren (Series 6+) in unter 2 ms ausgeführt werden.
