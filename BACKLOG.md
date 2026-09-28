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
- [x] ~~**Audit session and alarm state transitions.**~~ Reviewed start/stop cleanup, stale-sensor fallback, HealthKit failure, wake/feedback cancellation, grace expiry, and repeated-alert gating. Fixed a late authorization callback that could update a stopped session. Workout interruption and haptic delivery still need the physical-watch check below.
- [x] ~~**Make sensor readiness explicit.**~~ The active screen reports when motion is unavailable and shows “Motion only” after HealthKit authorization when no fresh pulse is available. Physical watch behavior remains to validate.
- [ ] **Validate live background operation and battery on physical watches.** Confirm motion delivery and haptic behavior with screen off, wrist down, app backgrounded, workout interruptions, low power, and competing workout sessions. Apple documents background execution during an active workout, but also advises limiting CPU use: [Running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions).

### P1 — Improve detection quality and response time

- [x] ~~**Replace the single averaged movement score with robust short and long windows.**~~ MotionManager now keeps a one-second movement estimate, a five-second estimate, the latest sample delta for immediate wake gestures, and sample timestamps; the detector rejects stale samples. Further tuning waits for labeled watch data.
- [x] ~~**Review posture features in device coordinates.**~~ Code review confirmed the detector uses pitch change over a rolling window rather than a static angle as sleep evidence. Added a note that Core Motion attitude pitch is reference-frame relative. Wrist orientation coverage still needs the physical-watch protocol.
- [x] ~~**Review pulse freshness and baseline logic.**~~ The baseline uses the first three valid samples and slow adaptation; samples must be 30–220 bpm, distinct, and under 20 seconds old by HealthKit’s sample timestamp. Missing/stale pulse falls back to motion-only evidence. Device behavior remains in the watch validation block.
- [x] ~~**Rework feedback adaptation to match the product rule.**~~ A false-alarm label now records the count without globally changing timing or sensor weights. Similar examples are handled by the three-example personal pattern veto; confirmed positives retain their cautious sensitivity adjustment.
- [x] ~~**Audit personal-pattern distance and sample handling.**~~ Named the feature scales and match radii, added finite/shape/label checks, confirmed 3 awake matches and positive-example protection, and retained 40 sleep / 60 awake class limits inside a 100-example cap. Similarity radii remain heuristics for the labeled-data threshold evaluation below. Examples do not expire automatically; users can reset them. No age cutoff was chosen without evidence.
- [ ] **Tune thresholds only against labeled replay and watch sessions.** Compare sensitivity, false alarms per hour, and detection latency across people and contexts. Do not select a setting from overall accuracy alone when positives are rare.
- [ ] **Add a personal calibration flow after its signal is validated.** The UI is buildable, but applying a quiet-awake baseline to the motion threshold without labeled positive and awake sessions could make detection slower or less reliable. First measure this approach in the replay/watch study; then build the flow with skip and reset controls if it improves the held-out tradeoff.

### P2 — Make the watch experience discreet and polished

- [x] ~~**Redesign the active screen as a neutral focus/watch face.**~~ Removed the explanatory start-screen subtitle and visible manual logging instruction; manual event logging now uses a long press or an accessible VoiceOver action.
- [x] ~~**Polish alert and feedback UI.**~~ Feedback controls now use icons with accessible labels, and the alert copy is “Check in”; five-second post-wake feedback remains in place.
- [ ] **Validate haptic patterns on device.** Code now steps gentle and medium preferences through bounded pattern levels and stops on wake or feedback. Confirm perceptibility, watchOS behavior, comfort, and stoppage timing on physical watches. A continuous alarm is a repeated sequence of discrete calls.
- [x] ~~**Simplify Settings and copy.**~~ Renamed adaptive sensitivity in plain language and explained that feedback-driven heuristics are not a sleep diagnosis. Learned counts are shown as counts rather than an accuracy percentage.
- [ ] **Finish on-device accessibility and presentation pass.** Code uses scalable text styles, stronger status contrast, labeled controls, and a VoiceOver missed-event action. Check actual Dynamic Type sizes, contrast, localization, small watch layouts, icon, and screenshots on device.

### P3 — Privacy, release readiness, and research

- [x] ~~**Review telemetry purpose, fields, retention, and deletion.**~~ Settings explains feedback capture, offers deletion, and notes a 1,000-window cap. Sensor windows, diagnostics, and replay examples are excluded from device backups.
- [x] ~~**Align HealthKit permission copy and workout lifecycle with actual behavior.**~~ Removed workout read/write authorization and the inaccurate update-purpose text. The app explains heart-rate reading and discards its background workout session. Physical device behavior still needs validation.
- [x] ~~**Run a privacy and permission review.**~~ Source review found no network transfer APIs; sensor/replay files are local and excluded from backups. HealthKit requests read access to heart rate only, and unavailable data falls back to motion-only mode.
- [x] ~~**Create a real-watch validation protocol.**~~ Added [REAL_WATCH_VALIDATION.md](REAL_WATCH_VALIDATION.md) with session blocks, label guidance, per-person metrics, battery comparison, and a held-out evaluation plan.
- [x] ~~**Set provisional release criteria.**~~ Added explicit internal targets and minimum participant/event coverage to `REAL_WATCH_VALIDATION.md`. They are product goals, not medical standards, and must be checked against held-out data.
- [x] ~~**Reassess the product claim and intended use.**~~ Settings and validation materials describe Focus as an attention aid and state that wrist motion and pulse cannot confirm sleep.

## Notes and decisions

- The current source tree already contains uncommitted work when this backlog was created. Keep those changes intact; review them before merging backlog items that overlap.
- Initial research supports a cautious design: wrist immobility alone can classify quiet wake as sleep, and background workout sessions provide runtime but require explicit lifecycle and battery validation.
- Implemented in this pass: replay evaluator, no global negative-feedback threshold changes, lower-profile active UI, a local data deletion action, and heart-rate permission copy aligned with the discarded workout lifecycle.
- Follow-up implementation: opt-in bounded decision traces, a fix for a late HealthKit authorization callback after session stop, and exclusion of saved sensor material from backups.
- A source-level lifecycle audit is complete; physical watch behavior under workout interruption and background haptics remains unverified.
- Code reviews now cover posture and pulse handling. HealthKit freshness uses the timestamp returned for its latest sample ([Apple HealthKit documentation](https://developer.apple.com/documentation/healthkit/hkstatistics/mostrecentquantitydateinterval())). An internal release-gate proposal is documented.
- The only open work is gated by physical watches or representative participant-labeled data: background/battery and haptic validation, on-device accessibility/layout checks, threshold and pattern-radius evaluation, and evidence for any calibration flow.
- The code review found separate short/long movement windows were already present; the backlog now records them as complete. The current detector still needs labeled data to tune their thresholds.
- Still requiring device/data access: replay evaluation on representative labeled data, real-watch lifecycle and battery checks, false-alarm/latency tuning, and validation across people and contexts.
- Last reviewed: 2026-09-28.
