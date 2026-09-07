# نظام إدارة المتقدمين الأكاديميين

تطبيق ويب عربي لإدارة بيانات المتقدمين الأكاديميين بعد تنظيف ملف Excel وتصنيف التخصصات.

## بيانات الدخول التجريبية

- اسم المستخدم: `admin`
- كلمة المرور: `admin123`

## الملفات المهمة

- `index.html`: واجهة التطبيق.
- `styles.css`: تنسيق الواجهة.
- `app.js`: منطق تسجيل الدخول، تحميل البيانات، البحث، الفلاتر، والتقارير.
- `public/data/applicants_final_categorized.csv`: قاعدة المتقدمين النهائية.
- `public/data/missing_data_report.csv`: تقرير النواقص للموظف.
- `public/data/specialty_mismatches_only.csv`: تقرير اختلافات التخصصات.
- `public/data/summary_by_main_category.csv`: ملخص الفئات الرئيسية.

## النشر

يمكن رفع المشروع إلى GitHub ثم ربطه مع Vercel كموقع static.

في المرحلة التالية يمكن استبدال ملفات CSV بقاعدة Supabase وجعل تسجيل الدخول عبر Supabase Auth.
