# Sensor replay format, version 1

The host evaluator replays the production rule engine against timestamped sensor streams and reports sleep onset sensitivity, median alert latency, false alerts per monitored hour, and timestamp gaps. It does not train a model or establish clinical accuracy. Replay only data with meaningful labels; keep files local and deidentified.

Build and run from the repository root:

```sh
swiftc -o /tmp/evaluate-sensor-replays \
  'SleepyJoe Watch App/Managers/SleepDetectionEngine.swift' \
  'SleepyJoe Watch App/ML/FeatureExtractor.swift' \
  tools/evaluate_sensor_replays.swift
/tmp/evaluate-sensor-replays path/to/replays.json
```

Input is one JSON object with a format version and one or more sessions. Every row represents a 10 Hz sensor sample. Acceleration values use the same units as Core Motion user acceleration; pitch is in degrees. `truth` is `awake` or `sleep`, with the first awake-to-sleep transition marking the reported onset. Heart-rate drop is optional and relative to the session baseline. A missing row is a sample gap.

```json
{
  "formatVersion": 1,
  "sessions": [
    {
      "id": "deidentified-session-01",
      "frames": [
        {
          "seconds": 0.0,
          "x": 0.002,
          "y": -0.001,
          "z": 0.003,
          "pitchDegrees": 4.2,
          "heartRateDropPercentage": null,
          "truth": "awake"
        }
      ]
    }
  ]
}
```

The current simple adapter feeds consecutive acceleration samples to the engine's short movement input. Review this assumption before interpreting results; collected Apple Watch background updates may have different timing and quality. The evaluator's sensitivity and latency are meaningful only when the onset labels and sampling cadence are reliable.
