# نشر البرنامج على Vercel

## الطريقة المقترحة

1. افتح Vercel.
2. اختر Add New Project.
3. اختر مستودع GitHub:
   `hrhebronbranch-design/HR`
4. اترك الإعدادات الافتراضية لأن المشروع Static.
5. اضغط Deploy.

## بعد ربط Supabase

حدّث ملف `config.js` بقيم Supabase ثم ارفع التعديل إلى GitHub. سيقوم Vercel بإعادة النشر تلقائيًا.

## ملاحظة

مفتاح Supabase `anon public key` ليس كلمة سر خاصة. هو مفتاح عام مصمم للاستخدام في المتصفح مع سياسات RLS.
