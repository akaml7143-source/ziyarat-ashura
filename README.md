# تطبيق زيارة عاشوراء

حزمة مشروع Flutter للرفع إلى مستودع GitHub وبناء APK عبر GitHub Actions.

## الملفات
- `lib/main.dart`: ملف التطبيق الكامل.
- `assets/ashura_icon.png`: أيقونة التطبيق المعتمدة.
- `assets/wallpaper_1326_1793992364813.jpg`: خلفية شاشة البداية.
- `assets/listening_background.jpg`: صورة صفحة الاستماع الثابتة.
- `.github/workflows/build-apk.yml`: بناء APK يدوياً فقط عبر GitHub Actions.

## ملاحظات مهمة قبل اعتبار الصوت مكتملاً
توجد تسجيلات القرّاء التالية ضمن مجلد `assets/`، ويعمل تشغيلها محلياً دون الحاجة إلى اتصال بالإنترنت:

- `shibr_maalla.mp3`
- `baqir_almaqdisi.mp3`
- `basim_alkarbalaei.mp3`
- `ahmed_alftlawi.mp3`
- `mohammed_baqir_alkhaqani.mp3`
- `aba_thar_alhelwachi.mp3`
- `ali_alkabi.mp3`
- `mahdi_samawati.mp3`
- `ammar_alkinani.mp3`
- `shibr_maalla_abbas.mp3` (زيارة الإمام العباس بصوت الشيخ شبر معله)

## طريقة بناء APK

تحديث التطبيق: 2026/11/13

التحقق الأخير من البناء: 2026/11/13
لبناء APK، افتح تبويب Actions في المستودع، واختر Build Ziyarat Ashura APK، ثم اضغط Run workflow على فرع main. اسم التطبيق الظاهر على الهاتف مضبوط في workflow على: `زيارة عاشوراء`.

## ملاحظة الخط
عنوان شاشة البداية مضبوط على عائلة `AmiriQuran` بوصفها أقرب خط قرآني متاح في الكود المسترجع؛ ملف خط عثماني مستقل لم يكن موجوداً ضمن الملفات المسترجعة، لذلك يلزم إرفاق ملف الخط العثماني الأصلي إذا كان المطلوب مطابقته حرفياً.


آخر تحديث للتطبيق: 2026/11/13


مراجعة تنسيق النصوص والمنبّهات: 2026/11/13


تم تحديث واجهات التطبيق ومحتوى الأحاديث والمنبّهات في إصدار نوفمبر 2026.


تحديث واجهة الترحيب ومحتوى فضل الزيارة والمنبّهات في الإصدار الحالي.


<!-- Trigger Android APK build after Dart syntax correction. -->


<!-- Trigger APK build for latest welcome and reader-name updates. -->
