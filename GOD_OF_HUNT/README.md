# GOD_OF_HUNT

اندیکاتور شکار نقدینگی بر پایهٔ متدولوژی ABCD — ادامهٔ مستقل پروژهٔ
`ABHunter/` (نسخهٔ 2.77) با نام و شماره‌گذاری جدید.

پوشهٔ `ABHunter/` دست‌نخورده می‌ماند و فقط مرجع است. قواعد روش و درس‌های
مهندسی همان‌جا هستند و اینجا هم لازم‌الاجرا:

- [`../ABHunter/METHODOLOGY.md`](../ABHunter/METHODOLOGY.md) — قواعد خود روش ABCD
- [`../ABHunter/LESSONS.md`](../ABHunter/LESSONS.md) — قواعد مهندسی (شبیه‌ساز، زنجیرهٔ نامزد، …)

## فایل‌ها

| فایل | نقش |
|---|---|
| `GOD_OF_HUNT.mq5` | اندیکاتور چارت: رسم AB و چرخهٔ عمر الگو |
| `GOD_OF_HUNT_Core.mqh` | منطق مشترک تشخیص و چرخهٔ عمر |
| `GOD_OF_HUNT_Scanner.mq5` | اسکنر چند نمادی با جدول و نوتیفیکیشن |
| `tools/` | شبیه‌ساز توسعه (`sim` / `diff` / `states`) — در متاتریدر کپی نشود |

پیشوند همهٔ آبجکت‌ها و متغیرهای سراسری از `ABH`/`abh` به `GOH`/`goh` تغییر
کرده، پس GOD_OF_HUNT و ABHunter می‌توانند هم‌زمان روی یک ترمینال نصب باشند
بدون اینکه آبجکت‌ها یا وضعیت هم را خراب کنند. اسکنر GOD_OF_HUNT فقط چارتی را
پیدا می‌کند که اندیکاتور GOD_OF_HUNT رویش نصب است، نه ABHunter.

## تست قبل از هر تغییر در منطق تشخیص

```bash
cd GOD_OF_HUNT/tools
python3 mksim.py && python3 mkold.py
g++ -std=c++17 -O0 -w -o /tmp/sim    sim.cpp    && /tmp/sim
g++ -std=c++17 -O0 -w -o /tmp/diff   diff.cpp   && /tmp/diff
g++ -std=c++17 -O0 -w -o /tmp/states states.cpp && /tmp/states
```

عدد مرجع `diff` در v1.00: `5097 / 4764 / 1206 / 873` (همان v2.77 مبنا).

## چنجلاگ

### 1.00
- شروع پروژه: کپی کامل ABHunter v2.77 با نام GOD_OF_HUNT.
- تغییر همهٔ پیشوندهای آبجکت/متغیر سراسری (`ABH_→GOH_`، `abhst_→gohst_`،
  `ABHscan_→GOHscan_`، …) برای هم‌زیستی با نصب ABHunter.
- ابزارهای تست به `GOD_OF_HUNT/tools` منتقل و به هستهٔ جدید وصل شدند؛ هر سه
  تست با نتیجهٔ مرجع v2.77 سبز.
- هیچ تغییری در منطق تشخیص یا چرخهٔ عمر نیست.
