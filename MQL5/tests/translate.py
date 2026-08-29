#!/usr/bin/env python3
"""Rewrites ThreeCandlePattern.mqh into C++ so its logic can be unit tested.

Only two things need changing: MQL's array-reference parameter syntax
(`Type &name[]`) becomes a std::vector reference, and TCLLoadRates is
dropped because it talks to the terminal's history rather than to the
pattern logic under test.
"""
import re
import sys

src = open(sys.argv[1], encoding="utf-8").read()

# drop #property lines
src = re.sub(r"^#property.*$", "", src, flags=re.M)

# drop TCLLoadRates: it depends on CopyRates/TimeCurrent, not on pattern logic
start = src.index("int TCLLoadRates(")
# walk to the matching closing brace of the function body
depth, i = 0, src.index("{", start)
while True:
    if src[i] == "{":
        depth += 1
    elif src[i] == "}":
        depth -= 1
        if depth == 0:
            break
    i += 1
src = src[:start] + src[i + 1:]

# MQL array-reference parameters -> std::vector references
src = src.replace("const MqlRates &rates[]", "const std::vector<MqlRates> &rates")
src = src.replace("STCLPattern &result[]", "std::vector<STCLPattern> &result")

open(sys.argv[2], "w", encoding="utf-8").write('#include "mql5_shim.h"\n' + src)
