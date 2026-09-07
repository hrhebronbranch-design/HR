# إعداد Supabase

## 1. إنشاء المشروع

أنشئ مشروعًا جديدًا في Supabase، ثم افتح SQL Editor وشغل الملف:

`supabase/schema.sql`

## 2. استيراد البيانات

من Supabase Table Editor افتح جدول `applicants` ثم اختر Import CSV واستورد الملف:

`public/data/applicants_final_categorized.csv`

الأعمدة الموجودة في CSV مطابقة للأعمدة الأساسية في جدول `applicants`.

## 3. إنشاء مستخدم دخول

من Authentication > Users أنشئ مستخدمًا جديدًا ببريد وكلمة مرور.

في شاشة الدخول يمكن إدخال البريد في حقل "اسم المستخدم أو البريد".

## 4. ربط الواجهة

من Project Settings > API انسخ:

- Project URL
- anon public key

ثم ضع القيم في ملف `config.js`:

```js
window.HR_CONFIG = {
  supabaseUrl: "https://PROJECT.supabase.co",
  supabaseAnonKey: "PUBLIC_ANON_KEY",
};
```

بعدها سيقرأ البرنامج البيانات من Supabase. إذا تركت القيم فارغة سيقرأ من ملفات CSV المحلية.
