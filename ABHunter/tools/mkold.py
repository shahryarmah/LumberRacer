#!/usr/bin/env python3
"""Build sim_old.h: the CollectSwings from the user's original working
ShinMim.mq5, renamed to CollectSwingsOld so diff.cpp can run both detectors
side by side on the same candles.

The old file's detection inputs have the same names and the same defaults as
the current core, so sim_old.h reuses the globals sim_core.h already defines
and only carries the function body."""
import re, pathlib

SRC = pathlib.Path(__file__).parent / "ref_ShinMim.mq5"
OUT = pathlib.Path(__file__).parent / "sim_old.h"

text = SRC.read_text(encoding="utf-8")

start = text.index("int CollectSwings(")
end   = text.index("void BuildComposite(")
body  = text[start:end]

body = body.replace("int CollectSwings(", "int CollectSwingsOld(")
body = re.sub(r'&(\w+)\[\]', r'\1[]', body)
body = re.sub(r'(\w+)\[\]\s*;', r'\1[8192];', body)

OUT.write_text(body, encoding="utf-8")
print(OUT)
