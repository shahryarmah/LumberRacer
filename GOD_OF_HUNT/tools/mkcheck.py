#!/usr/bin/env python3
"""بررسی نحوی فایل های .mq5 با تبدیل به ++C و کامپایل با شیم mql5_stub.h.

این کامپایل واقعی MQL5 نیست (LESSONS.md بند ۵). هر خطا اول در شیم بررسی
شود، نه در سورس — مگر اینکه واقعا باگ باشد.

بدون آرگومان هیچ فایلی بررسی نمی‌شود؛ همیشه نام فایل ها را صریح بدهید:

    python3 mkcheck.py GOD_OF_HUNT.mq5 GOD_OF_HUNT_Scanner.mq5
"""
import re, sys, pathlib, subprocess, tempfile

HERE = pathlib.Path(__file__).parent
ROOT = HERE.parent
CORE = ROOT / "GOD_OF_HUNT_Core.mqh"


def clean(text):
    out = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("#property") or s.startswith("#include"):
            continue
        # input group "..."  فقط سربرگ پنجره تنظیمات است و متغیری نمی‌سازد
        if re.match(r'^\s*input\s+group\b', line):
            continue
        line = re.sub(r'^(\s*)input\s+', r'\1', line)
        # D'2026.01.01 00:00'  — لیترال تاریخ مخصوص MQL5 است و ++C ندارد
        line = re.sub(r"D'[^']*'", '0', line)
        line = re.sub(r'&(\w+)\[\]', r'\1[]', line)
        line = re.sub(r'(\w+)\[\]\s*;', r'\1[8192];', line)
        out.append(line)
    text = "\n".join(out)

    # ENUM_TIMEFRAMES در MQL از int قابل انتساب است؛ در ++C نیست. با int
    # جایگزین می‌شود و PERIOD_* ها در شیم مقدار عددی واقعی خود را دارند.
    text = re.sub(r'\bENUM_TIMEFRAMES\b', 'int', text)

    # ثابت های متاتریدر که فقط به عنوان آرگومان پاس می‌شوند؛ مقدارشان مهم نیست
    for pat in (r'\bclr[A-Za-z]+\b', r'\bOBJPROP_[A-Z_]+\b', r'\bOBJ_[A-Z_]+\b',
                r'\bCORNER_[A-Z_]+\b', r'\bBORDER_[A-Z_]+\b', r'\bSTYLE_[A-Z_]+\b',
                r'\bANCHOR_[A-Z_]+\b', r'\bCHARTEVENT_[A-Z_]+\b',
                r'\bCHART_[A-Z_]+\b', r'\bREASON_[A-Z_]+\b',
                r'\bPOSITION_[A-Z_]+\b', r'\bINIT_SUCCEEDED\b'):
        text = re.sub(pat, '0', text)

    # MQL5 ارجاع رو به جلو را مجاز می‌داند و ++C نه؛ پروتوتایپ ساخته می‌شود.
    # پروتوتایپ ها ابتدای متن می‌نشینند، پس تابعی که پارامترش نوع تعریف شده
    # در خود فایل است (struct/enum که هنوز تعریف نشده) پروتوتایپ نمی‌گیرد؛
    # چنین تابع هایی نباید قبل از تعریفشان صدا زده شوند.
    user_types = set(re.findall(r'(?:struct|enum)\s+(\w+)', text))
    protos = []
    for m in re.finditer(
            r'^(void|int|bool|long|double|string|color|datetime|ulong)\s+'
            r'(\w+)\s*\(([^;{]*?)\)\s*\{',
            text, re.MULTILINE | re.DOTALL):
        if m.group(2) == 'main':
            continue
        params = re.sub(r'=\s*[^,)]+', '', m.group(3))
        if user_types & set(re.findall(r'[A-Za-z_]\w*', params)):
            continue
        protos.append(f"{m.group(1)} {m.group(2)}({params});")

    return "\n".join(protos) + "\n" + text


def check(mq5_name):
    # اسکریپت های داخل tools هسته را اینکلود نمی‌کنند
    src = HERE / mq5_name
    with_core = True
    if not src.exists():
        src = ROOT / mq5_name
    else:
        with_core = False

    body = '#include "' + str(HERE / "mql5_stub.h") + '"\n'
    if with_core:
        body += clean(CORE.read_text(encoding="utf-8")) + "\n"
    body += (clean(src.read_text(encoding="utf-8")) + "\n" +
             "int main() { return 0; }\n")

    with tempfile.NamedTemporaryFile("w", suffix=".cpp", delete=False,
                                     encoding="utf-8") as f:
        f.write(body)
        cpp = f.name

    r = subprocess.run(["g++", "-std=c++17", "-fsyntax-only", "-w", cpp],
                       capture_output=True, text=True)
    print(("OK   " if r.returncode == 0 else "FAIL ") + mq5_name)
    if r.returncode != 0:
        print(r.stderr[:6000])
    return r.returncode


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: mkcheck.py <file.mq5> [more.mq5 ...]   (no default files!)")
        sys.exit(2)
    rc = 0
    for name in sys.argv[1:]:
        rc |= check(name)
    sys.exit(rc)
