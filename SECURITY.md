# راه‌اندازی امنیت (یک‌بار)

همهٔ رازها فقط در **GitHub → Settings → Secrets and variables → Actions** نگهداری می‌شوند.

| Secret | محتوا |
|---|---|
| `DEFAULT_SUBS_JSON` | آرایهٔ JSON اشتراک‌های رایگان: `[{"id":"..","name":"..","url":".."}]` (**الزامی** — بدون آن بیلد متوقف می‌شود) |
| `KEYSTORE_BASE64` | فایل keystore به‌صورت base64 |
| `KEYSTORE_PASSWORD` | رمز keystore |
| `KEY_ALIAS` | نام alias |
| `KEY_PASSWORD` | رمز کلید (اگر با رمز keystore یکی است خالی بگذار) |

## ساخت کلید امضای جدید در Termux
```
keytool -genkey -v -keystore new.keystore -alias hasan -keyalg RSA -keysize 4096 -validity 10000
base64 -w0 new.keystore
```
خروجی base64 را در `KEYSTORE_BASE64` بگذار و فایل `new.keystore` را جای امن نگه دار (داخل ریپو نه).

⚠️ کلیدِ عوض‌شده یعنی کاربران فعلی باید یک بار برنامه را پاک و دوباره نصب کنند
(اندروید بروزرسانی با امضای متفاوت را قبول نمی‌کند).

## وضعیت مخزن
کلید امضا دیگر در ریپو ردیابی نمی‌شود (`hasan.keystore` و `android-keystore.b64`
از ایندکس گیت خارج و در `.gitignore` قرار گرفته‌اند). اگر همین کلید قبلاً برای
نسخه‌های منتشرشده استفاده شده، آن را **افشاشده** فرض کن؛ عوض کردنش یعنی کاربران
فعلی باید برنامه را پاک و دوباره نصب کنند.

بیلد بدون `KEYSTORE_BASE64` و `KEYSTORE_PASSWORD` عمداً متوقف می‌شود
(قبلاً یک مسیر جایگزین با رمز ثابت داخل `build-apk.yml` بود که حذف شد).
