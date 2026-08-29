#!/usr/bin/env bash
# Translates ThreeCandlePattern.mqh into C++ and runs the pattern tests.
set -euo pipefail
cd "$(dirname "$0")"
python3 translate.py ../Indicators/ThreeCandleLevels/ThreeCandlePattern.mqh ThreeCandlePattern.gen.h
g++ -std=c++17 -Wall -Wextra -O1 -o test_pattern test_pattern.cpp
./test_pattern
