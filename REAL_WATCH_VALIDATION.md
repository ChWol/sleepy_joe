# Focus — Real Watch Validation Protocol

This protocol evaluates Focus as an attention aid. Wrist motion and heart rate cannot establish sleep onset on their own. A claim about physiologic sleep onset needs a stronger reference such as polysomnography (PSG).

## Before collecting data

Record the app commit, watch model, watchOS version, wrist/hand, band fit, settings, sensitivity, haptic strength, HealthKit permission state, and whether decision diagnostics are enabled. Use participant IDs rather than names. Keep any exported traces and labels local and access controlled; diagnostics omit raw motion, while explicitly submitted feedback windows contain sensor data.

Do not use the app as a safety device or for driving, operating machinery, clinical decisions, or other situations where a missed or delayed alert could cause harm. Stop a session if haptics cause discomfort.

## Session blocks

Run the same planned blocks for each participant, with the watch worn as it normally would be:

1. Quiet reading and listening, with arms supported and unsupported.
2. Typing, handwriting, and ordinary desk work.
3. Several wrist and forearm positions, including a fixed downward wrist, neutral wrist, and arm resting on a desk.
4. Standing, walking, and returning to stillness.
5. A naturally occurring drowsiness period, if one occurs. Do not induce sleep deprivation or ask participants to fall asleep.
6. A separate background/battery block with screen off, wrist down, and ordinary interaction with other watch apps. Include a competing workout session only as a controlled lifecycle check.

Record block start/end, interruptions, charging/power mode, and whether the watch or Focus was backgrounded. Repeat blocks on more than one day where practical.

## Ground truth and labels

- For an attention-aid evaluation, ask participants to press a timestamped marker when they first notice drowsiness and again when they feel alert. Record false alarms immediately with the app’s feedback action.
- Record missed drowsiness markers even when Focus did not alert. Do not infer that a quiet wrist means sleep.
- If evaluating sleep onset, pair the watch with PSG and have qualified scorers mark sleep onset. Self-report or another consumer wearable is not a PSG substitute.
- Keep participants separate between threshold/model tuning and held-out evaluation. Never put windows from one person in both sets.

## Metrics to report

Report every metric per participant and per condition, plus a pooled summary:

- False alerts per monitored hour.
- Fraction of labeled drowsiness/sleep onsets with an alert within 5, 10, 20, and 30 seconds.
- Median and 90th percentile time from ground-truth onset to alert, including missed events separately.
- Alerts per session, sensor gaps per hour, time in degraded motion-only mode, and session interruptions.
- Battery use over the same duration on a matched no-Focus day/session.
- Feedback completion rate and haptic dismissal method.

Use `tools/evaluate_sensor_replays.swift` for timestamped 10 Hz replay streams and record its output with the app commit. The evaluator's 30-second match window is a reporting convention, not a product guarantee. Review raw event timing and labels before using aggregate numbers.

## Decision log

Use these as provisional internal release gates for an attention aid, not clinical cutoffs:

- False alerts: at most 0.1 per monitored hour overall, and at most 0.2 per hour in any predefined awake condition.
- Self-reported drowsiness events: at least 80% get an alert within 30 seconds overall; report every participant separately so pooled results cannot hide a poor fit.
- Alert latency: median at most 10 seconds and 90th percentile at most 30 seconds for detected events.
- Battery: complete an eight-hour active session with at least 20% charge remaining on each tested watch model.
- Coverage: at least 15 participants, three watch models/sizes, 100 awake monitoring hours, and 30 labeled drowsiness events before any public reliability claim. Use participant-separated tuning and held-out evaluation.

These are product targets chosen to reflect the requested low false-alarm rate and quick response; they are not established medical standards. If the data cannot meet them, keep the feature experimental and report the measured tradeoff rather than loosening a metric after seeing the held-out results. Preserve the held-out set for final evaluation.
