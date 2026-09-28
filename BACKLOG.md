# SleepyJoe / Focus — Product Backlog

Living, ordered list for making Focus a dependable, discreet drowsiness support tool. Update this file as work lands; completed work stays visible with strikethrough so we keep a record. Priorities can change when watch data gives us evidence.

## Product guardrails

- Optimize for useful early warnings with a low false alarm rate. Report both; do not tune either from intuition alone.
- Treat wrist motion and pulse as indirect clues, not proof of sleep or a medical diagnosis. Quiet wakefulness is a known weakness of actigraphy: [Marino et al., PSG comparison](https://pmc.ncbi.nlm.nih.gov/articles/PMC3792393/).
- Keep the experimental CoreML model out of live decisions until it is validated on real, person-separated data.
- Keep active-session UI calm and ordinary. Make the alert unmistakable to the wearer while keeping the screen discreet to others.
- Explain and minimize saved sensor data; make deletion easy to find.

## Completed foundation

- ~~Rule-based detector requires fresh motion and combines stillness with a posture change, pulse trend, or exceptional stillness.~~
- ~~Personal false-alarm patterns are intended to suppress ambiguous cues, while a similar confirmed event can protect against suppression.~~
- ~~Alarm flow supports wake motion, feedback taps, a grace period, and an expiring feedback prompt.~~
- ~~CoreML training/inference is not used by the live detector.~~
- ~~Added host-side detection logic checks for stale samples, quiet sitting, pulse cue, personal patterns, posture cue, long stillness, and feature 6.~~

## Ordered backlog

### P0 — Make behavior observable and safe to improve

- [x] ~~**Build a labeled sensor replay format and evaluator.**~~ Added a versioned JSON timeline format and host-side evaluator that replays the production rule engine and reports sensitivity, median latency, false alerts per hour, and sample gaps. See `tools/SENSOR_REPLAY_FORMAT.md`. Requires meaningful labels before interpreting results.
- [x] ~~**Add detector decision traces.**~~ Added an opt-in, local-only trace of candidates, alerts, feedback, wake cancellation, grace-period changes, sensor gaps, confidence, thresholds, and sample age. It stores no raw motion and is removed by Delete saved sensor data. The trace is bounded to 5,000 events.
- [ ] **Audit session and alarm state transitions.** Check that stop, stale sensors, HealthKit denial/failure, workout interruption, wake gesture, feedback, grace expiry, and repeated alarms always leave timers, haptics, and prompts in a valid state.
- [x] ~~**Make sensor readiness explicit.**~~ The active screen reports when motion is unavailable and shows “Motion only” after HealthKit authorization when no fresh pulse is available. Physical watch behavior remains to validate.
- [ ] **Validate live background operation and battery on physical watches.** Confirm motion delivery and haptic behavior with screen off, wrist down, app backgrounded, workout interruptions, low power, and competing workout sessions. Apple documents background execution during an active workout, but also advises limiting CPU use: [Running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions).

### P1 — Improve detection quality and response time

- [ ] **Replace the single averaged movement score with robust short and long windows.** Preserve brief corrective movements, sustained stillness, signal quality, and sampling gaps separately so a five-second average cannot hide a transition.
- [ ] **Review posture features in device coordinates.** Current pitch comes from attitude pitch and a fixed relative drop heuristic. Check wrist orientation differences and arm positions; use calibrated baseline, angular velocity, and gravity orientation where they improve repeatability.
- [ ] **Review pulse freshness and baseline logic.** Confirm the trend is relative to a suitable personal seated baseline, bound the age of samples, and test missing/noisy pulse. Never let a stale pulse value silently support an alarm.
- [x] ~~**Rework feedback adaptation to match the product rule.**~~ A false-alarm label now records the count without globally changing timing or sensor weights. Similar examples are handled by the three-example personal pattern veto; confirmed positives retain their cautious sensitivity adjustment.
- [ ] **Audit personal-pattern distance and sample handling.** Check feature scaling, duplicates, missing/invalid values, class counts, stale examples, and persistence limits. Keep labels tied to the frozen pre-alarm window; never train on wake-up motion.
- [ ] **Tune thresholds only against labeled replay and watch sessions.** Compare sensitivity, false alarms per hour, and detection latency across people and contexts. Do not select a setting from overall accuracy alone when positives are rare.
- [ ] **Add an explicit calibration flow.** Collect a short quiet-awake baseline in typical use posture, explain what it does, allow skip/reset, and keep calibration from claiming it can detect sleep by itself.

### P2 — Make the watch experience discreet and polished

- [x] ~~**Redesign the active screen as a neutral focus/watch face.**~~ Removed the explanatory start-screen subtitle and visible manual logging instruction; manual event logging now uses a long press or an accessible VoiceOver action.
- [x] ~~**Polish alert and feedback UI.**~~ Feedback controls now use icons with accessible labels, and the alert copy is “Check in”; five-second post-wake feedback remains in place.
- [ ] **Review haptic patterns on device.** Confirm the repeating sequence is supported, perceptible, and stoppable at the next sensor event. Offer an escalating but bounded pattern, and make intensity/preferences clear. A “continuous” loop is necessarily a sequence of discrete haptic calls.
- [x] ~~**Simplify Settings and copy.**~~ Renamed adaptive sensitivity in plain language and explained that feedback-driven heuristics are not a sleep diagnosis. Learned counts are shown as counts rather than an accuracy percentage.
- [ ] **Finish accessibility and presentation pass.** Check Dynamic Type where applicable, VoiceOver actions, contrast, localization, small watch sizes, icon, and screenshots.

### P3 — Privacy, release readiness, and research

- [x] ~~**Review telemetry purpose, fields, retention, and deletion.**~~ Settings explains feedback capture, offers deletion, and notes a 1,000-window cap. Sensor windows, diagnostics, and replay examples are excluded from device backups.
- [x] ~~**Align HealthKit permission copy and workout lifecycle with actual behavior.**~~ Removed workout read/write authorization and the inaccurate update-purpose text. The app explains heart-rate reading and discards its background workout session. Physical device behavior still needs validation.
- [ ] **Run a privacy and permission review.** Verify no sensor payload leaves the watch, inspect app entitlements and HealthKit types, and document behavior when permissions are declined or revoked.
- [ ] **Create a real-watch validation protocol.** Include quiet desk work, reading/listening, varied arm/wrist positions, walking, fatigue/drowsiness reports, missing pulse, charging, background use, and battery. Where feasible, compare event labels with a stronger reference such as PSG; consumer wearable papers show motion plus pulse can help, but performance depends on validation conditions: [de Zambotti et al.](https://pmc.ncbi.nlm.nih.gov/articles/PMC7355403/).
- [ ] **Set release criteria before calling detection reliable.** Agree on acceptable false alarms per hour, minimum event sensitivity, latency target, battery budget, and required participant diversity based on collected evidence.
- [ ] **Reassess the product claim and intended use.** Keep Focus positioned as an attention aid unless the evidence and applicable review support stronger claims.

## Notes and decisions

- The current source tree already contains uncommitted work when this backlog was created. Keep those changes intact; review them before merging backlog items that overlap.
- Initial research supports a cautious design: wrist immobility alone can classify quiet wake as sleep, and background workout sessions provide runtime but require explicit lifecycle and battery validation.
- Implemented in this pass: replay evaluator, no global negative-feedback threshold changes, lower-profile active UI, a local data deletion action, and heart-rate permission copy aligned with the discarded workout lifecycle.
- Follow-up implementation: opt-in bounded decision traces, a fix for a late HealthKit authorization callback after session stop, and exclusion of saved sensor material from backups.
- Still requiring device/data access: replay evaluation on representative labeled data, real-watch lifecycle and battery checks, false-alarm/latency tuning, and validation across people and contexts.
- Last reviewed: 2026-09-28.
