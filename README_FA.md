# نت‌خوان پیانو — نسخه 1.3.4

این بسته شامل سورس Flutter، تست‌ها، پروژه Android و GitHub Actions برای ساخت APK است.

## ساخت خودکار APK در GitHub

1. محتویات این ZIP را مستقیماً در ریشه مخزن GitHub قرار دهید؛ پوشه‌های `.github`، `android`، `lib` و فایل `pubspec.yaml` باید در ریشه مخزن باشند.
2. تغییرات را Commit و Push کنید.
3. در تب Actions، گردش‌کار **Build Android APK** را اجرا کنید.
4. پس از موفقیت، فایل APK را از بخش Artifacts دریافت کنید.

Workflow مسیر پروژه را هم در ریشه مخزن و هم در پوشه داخلی پیدا می‌کند. پیش از ساخت، Gradle 8.14.3 را از توزیع رسمی دریافت می‌کند، Wrapper را از همان نسخه تولید می‌کند و نسخه واقعی Wrapper را کنترل می‌کند. اگر نسخه 8.9 اجرا شود، Workflow پیش از Build متوقف می‌شود.

## ساخت محلی

```bash
flutter pub get
flutter test
flutter build apk --release
```

خروجی معمول:
`build/app/outputs/flutter-apk/app-release.apk`

## یادداشت انتشار

تنظیم امضای Release فعلی برای تست داخلی است و از debug signing استفاده می‌کند. برای انتشار عمومی در Google Play باید keystore اختصاصی و امن پیکربندی شود.
