#!/usr/bin/env python3
"""Build a runnable C++ copy of GOD_OF_HUNT_Core so the detection logic can be
executed on synthetic candles instead of guessed at from screenshots."""
import re, pathlib

SRC = pathlib.Path("/home/user/LumberRacer/GOD_OF_HUNT/GOD_OF_HUNT_Core.mqh")
OUT = pathlib.Path(__file__).parent / "sim_core.h"

def clean(text):
    out = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("#property") or s.startswith("#include"):
            continue
        # input group "..."  فقط سربرگ پنجره تنظیمات است و متغیری نمی‌سازد
        if re.match(r'^\s*input\s+group\b', line):
            continue
        line = re.sub(r'^(\s*)input\s+', r'\1', line)   # قابل تغییر در تست
        line = re.sub(r'&(\w+)\[\]', r'\1[]', line)
        line = re.sub(r'(\w+)\[\]\s*;', r'\1[8192];', line)
        out.append(line)
    return "\n".join(out)

def strip_ui_layout(text):
    """Drop the panel-sizing block. It is pure MetaTrader UI (screen DPI, button
    geometry) and has no bearing on detection, so the simulator neither needs it
    nor has the terminal calls it depends on."""
    begin, end = "//<<< UI-LAYOUT-BEGIN", "//>>> UI-LAYOUT-END"
    if begin not in text:
        return text
    head, rest = text.split(begin, 1)
    _, tail = rest.split(end, 1)
    return head + tail

text = clean(strip_ui_layout(SRC.read_text(encoding="utf-8")))

# tunables stay writable so the sim can isolate one rule at a time
for name in ("MaxPatternDays", "RetraceMaxPercent", "RetraceMinPercent",
             "MinRetraceCandles", "AbOppositePercent", "MomentumMinPercent",
             "MaxRetraceBars"):
    text = text.replace("const int    " + name, "int " + name)
    text = text.replace("const double " + name, "double " + name)

# Instrument every invalidation in EvaluateLifecycle
s2 = text.index("void EvaluateLifecycle")
e2 = text.index("// کاهش زنجیره AB")
b2 = text[s2:e2].split("\n")
for n, ln in enumerate(b2):
    if "s.state = AB_INVALID;" in ln:
        b2[n] = ln.replace("s.state = AB_INVALID;",
                           'DBG("lifecycle", %d); s.state = AB_INVALID;' % n)
text = text[:s2] + "\n".join(b2) + text[e2:]

# Instrument every rejection in ValidateAB with the line it fired on.
start = text.index("bool ValidateAB")
end   = text.index("int CollectSwings")
body  = text[start:end]
lines = body.split("\n")
for n, ln in enumerate(lines):
    if "return false;" in ln:
        tag = f'DBG("ValidateAB", {n})'
        lines[n] = ln.replace("return false;", "{ %s; return false; }" % tag)
body = "\n".join(lines)
text = text[:start] + body + text[end:]

OUT.write_text(text, encoding="utf-8")
print(OUT)
