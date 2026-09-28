#!/bin/sh
set -eu
swiftc -o /private/tmp/sleepyjoe-detection-tests \
  'SleepyJoe Watch App/Managers/SleepDetectionEngine.swift' \
  'SleepyJoe Watch App/ML/FeatureExtractor.swift' \
  tests/DetectionLogicTests.swift
/private/tmp/sleepyjoe-detection-tests
