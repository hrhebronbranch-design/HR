const DATA_PATHS = {
  applicants: "./public/data/applicants_final_categorized.csv",
  missing: "./public/data/missing_data_report.csv",
  specialtyReview: "./public/data/specialty_mismatches_only.csv",
  mainSummary: "./public/data/summary_by_main_category.csv",
};

const state = {
  applicants: [],
  missing: [],
  specialtyReview: [],
  mainSummary: [],
  filteredApplicants: [],
};

const credentials = {
  username: "admin",
  password: "admin123",
};

let supabaseClient = null;

function getSupabaseClient() {
  const config = window.HR_CONFIG || {};
  if (!config.supabaseUrl || !config.supabaseAnonKey || !window.supabase) return null;
  if (!supabaseClient) {
    supabaseClient = window.supabase.createClient(config.supabaseUrl, config.supabaseAnonKey);
  }
  return supabaseClient;
}

function isSupabaseEnabled() {
  return Boolean(getSupabaseClient());
}

const pageTitles = {
  dashboard: "لوحة التحكم",
  applicants: "المتقدمون",
  missing: "مراجعة النواقص",
  specialties: "مراجعة التخصصات",
  reports: "التقارير",
};

const applicationStatuses = ["جديد", "قيد المراجعة", "ناقص", "مقابلة", "مقبول", "مرفوض"];
const editableFields = [
  "new_number",
  "full_name",
  "phone",
  "mobile",
  "national_id",
  "birth_date",
  "main_category",
  "sub_category",
  "specialty_text",
  "approved_specialty",
  "specialty_review_status",
  "graduation_university",
  "graduation_year",
  "original_paper",
  "source_sheet",
  "application_status",
  "notes",
];

let currentApplicant = null;

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function toDbValue(value) {
  const trimmed = String(value ?? "").trim();
  return trimmed === "" ? null : trimmed;
}

function parseCsv(text) {
  const clean = text.replace(/^\uFEFF/, "");
  const rows = [];
  let row = [];
  let value = "";
  let inQuotes = false;

  for (let i = 0; i < clean.length; i++) {
    const char = clean[i];
    const next = clean[i + 1];

    if (char === '"' && inQuotes && next === '"') {
      value += '"';
      i++;
    } else if (char === '"') {
      inQuotes = !inQuotes;
    } else if (char === "," && !inQuotes) {
      row.push(value);
      value = "";
    } else if ((char === "\n" || char === "\r") && !inQuotes) {
      if (char === "\r" && next === "\n") i++;
      row.push(value);
      if (row.some((cell) => cell.trim() !== "")) rows.push(row);
      row = [];
      value = "";
    } else {
      value += char;
    }
  }

  if (value || row.length) {
    row.push(value);
    rows.push(row);
  }

  const headers = rows.shift() || [];
  return rows.map((cells) => {
    const record = {};
    headers.forEach((header, index) => {
      record[header] = cells[index] || "";
    });
    return record;
  });
}

async function loadCsv(path) {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`Cannot load ${path}`);
  return parseCsv(await response.text());
}

function byId(id) {
  return document.getElementById(id);
}

function uniqueValues(rows, key) {
  return [...new Set(rows.map((row) => row[key]).filter(Boolean))].sort((a, b) => a.localeCompare(b, "ar"));
}

function fillSelect(select, label, values) {
  select.innerHTML = `<option value="">${label}</option>`;
  values.forEach((value) => {
    const option = document.createElement("option");
    option.value = value;
    option.textContent = value;
    select.appendChild(option);
  });
}

function refreshIcons() {
  if (window.lucide) window.lucide.createIcons();
}

function renderDashboard() {
  byId("totalApplicants").textContent = state.applicants.length.toLocaleString("ar");
  byId("totalMainCategories").textContent = uniqueValues(state.applicants, "main_category").length.toLocaleString("ar");
  byId("totalMissing").textContent = state.missing.length.toLocaleString("ar");
  byId("totalSpecialtyReview").textContent = state.specialtyReview.length.toLocaleString("ar");

  const max = Math.max(...state.mainSummary.map((row) => Number(row.applicants || 0)));
  byId("mainCategoryBars").innerHTML = state.mainSummary
    .map((row) => {
      const count = Number(row.applicants || 0);
      const width = max ? Math.round((count / max) * 100) : 0;
      return `
        <div class="bar-row">
          <span>${row.main_category}</span>
          <div class="bar-track"><div class="bar-fill" style="width:${width}%"></div></div>
          <strong>${count}</strong>
        </div>
      `;
    })
    .join("");

  const specialtyCounts = Object.entries(
    state.applicants.reduce((acc, row) => {
      acc[row.approved_specialty] = (acc[row.approved_specialty] || 0) + 1;
      return acc;
    }, {})
  )
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10);

  byId("topSpecialties").innerHTML = specialtyCounts
    .map(([name, count]) => `<div class="list-row"><span>${name}</span><strong>${count}</strong></div>`)
    .join("");
  refreshIcons();
}

function hasMissing(row) {
  return Boolean(row.issue_flags && row.issue_flags.trim()) || !row.national_id || !row.mobile || !row.graduation_university || !row.graduation_year;
}

function buildMissingRows(applicants) {
  const labels = [
    ["full_name", "الاسم"],
    ["national_id", "رقم الهوية"],
    ["birth_date", "تاريخ الميلاد"],
    ["graduation_university", "جامعة التخرج"],
    ["graduation_year", "سنة التخرج"],
    ["original_paper", "الورقة الأصلية"],
  ];

  return applicants
    .map((row) => {
      const missing = labels.filter(([key]) => !row[key]).map(([, label]) => label);
      if (!row.mobile && !row.phone) missing.push("الهاتف/الجوال");
      return {
        new_number: row.new_number,
        full_name: row.full_name,
        national_id: row.national_id,
        approved_specialty: row.approved_specialty,
        missing_fields: missing.join("; "),
        missing_count: missing.length,
        source_sheet: row.source_sheet,
        source_row: row.source_row,
      };
    })
    .filter((row) => row.missing_count > 0);
}

function buildSpecialtyReviewRows(applicants) {
  return applicants
    .filter((row) => row.specialty_review_status && row.specialty_review_status !== "مطابق")
    .map((row) => ({
      source_sheet: row.source_sheet,
      source_row: row.source_row,
      full_name: row.full_name,
      specialty_text: row.specialty_text,
      suggested_specialty: row.approved_specialty,
    }));
}

function buildMainSummary(applicants) {
  const grouped = applicants.reduce((acc, row) => {
    acc[row.main_category] ||= { main_category: row.main_category, applicants: 0, subCategories: new Set() };
    acc[row.main_category].applicants++;
    acc[row.main_category].subCategories.add(row.sub_category);
    return acc;
  }, {});
  return Object.values(grouped)
    .map((row) => ({
      main_category: row.main_category,
      applicants: row.applicants,
      sub_categories: row.subCategories.size,
    }))
    .sort((a, b) => b.applicants - a.applicants);
}

function applyApplicantFilters() {
  const search = byId("searchInput").value.trim().toLowerCase();
  const main = byId("mainCategoryFilter").value;
  const sub = byId("subCategoryFilter").value;
  const specialty = byId("specialtyFilter").value;
  const missing = byId("missingFilter").value;

  state.filteredApplicants = state.applicants.filter((row) => {
    const haystack = `${row.full_name} ${row.national_id} ${row.mobile} ${row.phone}`.toLowerCase();
    if (search && !haystack.includes(search)) return false;
    if (main && row.main_category !== main) return false;
    if (sub && row.sub_category !== sub) return false;
    if (specialty && row.approved_specialty !== specialty) return false;
    if (missing === "missing" && !hasMissing(row)) return false;
    if (missing === "complete" && hasMissing(row)) return false;
    return true;
  });

  renderApplicantsTable();
}

function renderApplicantsTable() {
  const rows = state.filteredApplicants.slice(0, 350);
  byId("applicantCount").textContent = `${state.filteredApplicants.length.toLocaleString("ar")} سجل`;
  byId("applicantsTable").innerHTML = rows
    .map((row) => {
      const completeness = hasMissing(row)
        ? '<span class="badge warn">ناقص</span>'
        : '<span class="badge ok">مكتمل</span>';
      const status = row.application_status || "جديد";
      return `
        <tr>
          <td>${escapeHtml(row.new_number)}</td>
          <td>${escapeHtml(row.full_name)}</td>
          <td>${escapeHtml(row.national_id || "")}</td>
          <td>${escapeHtml(row.mobile || row.phone || "")}</td>
          <td>${escapeHtml(row.main_category)}</td>
          <td>${escapeHtml(row.sub_category)}</td>
          <td>${escapeHtml(row.approved_specialty)}</td>
          <td>${escapeHtml(row.graduation_university || "")}</td>
          <td>${escapeHtml(row.graduation_year || "")}</td>
          <td><span class="badge ok">${escapeHtml(status)}</span> ${completeness}</td>
          <td><button class="row-action" type="button" data-open-applicant="${escapeHtml(row.id || row.new_number)}">استعراض</button></td>
        </tr>
      `;
    })
    .join("");
  refreshIcons();
}

function renderMissing() {
  byId("missingCount").textContent = `${state.missing.length.toLocaleString("ar")} سجل`;
  byId("missingTable").innerHTML = state.missing
    .slice(0, 500)
    .map(
      (row) => `
        <tr>
          <td>${escapeHtml(row.new_number)}</td>
          <td>${escapeHtml(row.full_name)}</td>
          <td>${escapeHtml(row.national_id || "")}</td>
          <td>${escapeHtml(row.approved_specialty)}</td>
          <td>${escapeHtml(row.missing_fields)}</td>
          <td>${escapeHtml(row.source_sheet)}</td>
        </tr>
      `
    )
    .join("");
  refreshIcons();
}

function renderSpecialtyReview() {
  byId("specialtyReviewCount").textContent = `${state.specialtyReview.length.toLocaleString("ar")} سجل`;
  byId("specialtyReviewTable").innerHTML = state.specialtyReview
    .slice(0, 500)
    .map(
      (row) => `
        <tr>
          <td>${escapeHtml(row.source_sheet)}</td>
          <td>${escapeHtml(row.full_name)}</td>
          <td>${escapeHtml(row.specialty_text)}</td>
          <td>${escapeHtml(row.suggested_specialty)}</td>
        </tr>
      `
    )
    .join("");
  refreshIcons();
}

function renderReports() {
  byId("mainCategoryTable").innerHTML = state.mainSummary
    .map(
      (row) => `
        <tr>
          <td>${row.main_category}</td>
          <td>${row.applicants}</td>
          <td>${row.sub_categories}</td>
        </tr>
      `
    )
    .join("");

  const subSummary = Object.values(
    state.applicants.reduce((acc, row) => {
      const key = `${row.main_category}||${row.sub_category}`;
      acc[key] ||= { main_category: row.main_category, sub_category: row.sub_category, applicants: 0 };
      acc[key].applicants++;
      return acc;
    }, {})
  ).sort((a, b) => b.applicants - a.applicants);

  byId("subCategoryTable").innerHTML = subSummary
    .map(
      (row) => `
        <tr>
          <td>${row.main_category}</td>
          <td>${row.sub_category}</td>
          <td>${row.applicants}</td>
        </tr>
      `
    )
    .join("");
  refreshIcons();
}

function setupFilters() {
  fillSelect(byId("mainCategoryFilter"), "كل الفئات الرئيسية", uniqueValues(state.applicants, "main_category"));
  fillSelect(byId("subCategoryFilter"), "كل الفئات الفرعية", uniqueValues(state.applicants, "sub_category"));
  fillSelect(byId("specialtyFilter"), "كل التخصصات", uniqueValues(state.applicants, "approved_specialty"));
  populateDatalists();
  ["searchInput", "mainCategoryFilter", "subCategoryFilter", "specialtyFilter", "missingFilter"].forEach((id) => {
    byId(id).oninput = applyApplicantFilters;
    byId(id).onchange = applyApplicantFilters;
  });
}

function switchView(viewName) {
  document.querySelectorAll(".nav-item").forEach((button) => {
    button.classList.toggle("active", button.dataset.view === viewName);
  });
  document.querySelectorAll(".view").forEach((view) => {
    view.classList.toggle("active-view", view.id === viewName);
  });
  byId("pageTitle").textContent = pageTitles[viewName];
  byId("addApplicantBtn").classList.toggle("hidden", viewName !== "applicants");
}

function exportFilteredApplicants() {
  const headers = Object.keys(state.filteredApplicants[0] || {});
  const escape = (value) => `"${String(value || "").replaceAll('"', '""')}"`;
  const csv = [headers.join(","), ...state.filteredApplicants.map((row) => headers.map((header) => escape(row[header])).join(","))].join("\n");
  const blob = new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "filtered_applicants.csv";
  link.click();
  URL.revokeObjectURL(url);
}

function getExportRows() {
  return state.filteredApplicants.map((row) => ({
    "الرقم": row.new_number || "",
    "الاسم": row.full_name || "",
    "رقم الهوية": row.national_id || "",
    "الهاتف": row.phone || "",
    "الجوال": row.mobile || "",
    "الفئة الرئيسية": row.main_category || "",
    "الفئة الفرعية": row.sub_category || "",
    "التخصص": row.approved_specialty || "",
    "الجامعة": row.graduation_university || "",
    "سنة التخرج": row.graduation_year || "",
    "حالة الطلب": row.application_status || "جديد",
  }));
}

function exportXlsx() {
  if (!window.XLSX) {
    alert("تعذر تحميل أداة تصدير XLSX.");
    return;
  }
  const rows = getExportRows();
  const workbook = XLSX.utils.book_new();
  const sheet = XLSX.utils.json_to_sheet(rows);
  sheet["!cols"] = [
    { wch: 8 }, { wch: 28 }, { wch: 14 }, { wch: 14 }, { wch: 14 },
    { wch: 26 }, { wch: 30 }, { wch: 26 }, { wch: 28 }, { wch: 12 }, { wch: 16 },
  ];
  XLSX.utils.book_append_sheet(workbook, sheet, "المتقدمون");
  XLSX.writeFile(workbook, "تقرير_المتقدمين.xlsx");
}

function exportPdf() {
  const rows = getExportRows();
  const report = window.open("", "_blank");
  if (!report) {
    alert("يرجى السماح بفتح النوافذ لتصدير PDF.");
    return;
  }
  const tableRows = rows
    .map((row) => `
      <tr>
        <td>${escapeHtml(row["الرقم"])}</td>
        <td>${escapeHtml(row["الاسم"])}</td>
        <td>${escapeHtml(row["رقم الهوية"])}</td>
        <td>${escapeHtml(row["الجوال"] || row["الهاتف"])}</td>
        <td>${escapeHtml(row["الفئة الرئيسية"])}</td>
        <td>${escapeHtml(row["التخصص"])}</td>
        <td>${escapeHtml(row["الجامعة"])}</td>
        <td>${escapeHtml(row["حالة الطلب"])}</td>
      </tr>
    `)
    .join("");

  const logoUrl = `${location.origin}/assets/alquds-open-university-logo.jpg`;
  report.document.write(`
    <!doctype html>
    <html lang="ar" dir="rtl">
      <head>
        <meta charset="utf-8" />
        <title>تقرير المتقدمين</title>
        <style>
          @import url("https://fonts.googleapis.com/css2?family=Cairo:wght@400;700;900&display=swap");
          @page { size: A4 landscape; margin: 14mm; }
          body { font-family: "Cairo", Tahoma, Arial, sans-serif; color: #111827; margin: 0; }
          header { display: flex; justify-content: space-between; align-items: center; border-bottom: 3px solid #0f6f61; padding-bottom: 14px; margin-bottom: 18px; }
          img { width: 72px; height: 72px; object-fit: contain; border-radius: 50%; }
          h1 { margin: 0 0 8px; font-size: 24px; }
          p { margin: 3px 0; color: #475467; font-size: 12px; }
          table { width: 100%; border-collapse: collapse; font-size: 10px; }
          th, td { border: 1px solid #d7e0df; padding: 6px; text-align: right; vertical-align: top; }
          th { background: #0f6f61; color: #fff; font-weight: 900; }
          tr:nth-child(even) td { background: #f7fafc; }
          .summary { display: flex; gap: 12px; margin-bottom: 14px; }
          .box { border: 1px solid #d7e0df; border-radius: 8px; padding: 8px 12px; min-width: 140px; }
          .box strong { display: block; font-size: 18px; color: #0f6f61; }
        </style>
      </head>
      <body>
        <header>
          <div>
            <h1>نظام إدارة المتقدمين الأكاديميين</h1>
            <p>اسم الموظف: الاستاذ فراس أبو زينة</p>
            <p>تصميم واعداد الموقع: الاستاذ احمد النتشة</p>
          </div>
          <img src="${logoUrl}" alt="شعار الجامعة" />
        </header>
        <section class="summary">
          <div class="box"><span>عدد السجلات</span><strong>${rows.length}</strong></div>
          <div class="box"><span>تاريخ التقرير</span><strong>${new Date().toLocaleDateString("ar")}</strong></div>
        </section>
        <table>
          <thead>
            <tr>
              <th>الرقم</th><th>الاسم</th><th>الهوية</th><th>الجوال</th>
              <th>الفئة</th><th>التخصص</th><th>الجامعة</th><th>الحالة</th>
            </tr>
          </thead>
          <tbody>${tableRows}</tbody>
        </table>
        <script>window.onload = () => setTimeout(() => window.print(), 300);</script>
      </body>
    </html>
  `);
  report.document.close();
}

function refreshDerivedData() {
  state.missing = buildMissingRows(state.applicants);
  state.specialtyReview = buildSpecialtyReviewRows(state.applicants);
  state.mainSummary = buildMainSummary(state.applicants);
  setupFilters();
  applyApplicantFilters();
  renderDashboard();
  renderMissing();
  renderSpecialtyReview();
  renderReports();
}

function populateDatalists() {
  const lists = [
    ["mainCategoryList", "main_category"],
    ["subCategoryList", "sub_category"],
    ["specialtyList", "approved_specialty"],
  ];
  lists.forEach(([id, key]) => {
    byId(id).innerHTML = uniqueValues(state.applicants, key)
      .map((value) => `<option value="${escapeHtml(value)}"></option>`)
      .join("");
  });
}

function setFormMessage(message, type = "") {
  const element = byId("formMessage");
  element.textContent = message;
  element.className = `form-message ${type}`.trim();
}

function findApplicant(identifier) {
  return state.applicants.find((row) => String(row.id || row.new_number) === String(identifier));
}

function openApplicantModal(applicant = null) {
  currentApplicant = applicant;
  const isNew = !applicant;
  const nextNumber = Math.max(0, ...state.applicants.map((row) => Number(row.new_number) || 0)) + 1;
  const row = applicant || {
    new_number: nextNumber,
    full_name: "",
    phone: "",
    mobile: "",
    national_id: "",
    birth_date: "",
    main_category: "",
    sub_category: "",
    specialty_text: "",
    approved_specialty: "",
    specialty_review_status: "مطابق",
    graduation_university: "",
    graduation_year: "",
    original_paper: "",
    source_sheet: "إدخال يدوي",
    application_status: "جديد",
    notes: "",
  };

  byId("applicantModalMode").textContent = isNew ? "إضافة متقدم جديد" : "استعراض وتعديل";
  byId("applicantModalTitle").textContent = isNew ? "متقدم جديد" : row.full_name || "بيانات المتقدم";
  byId("applicantId").value = row.id || "";

  const form = byId("applicantForm");
  editableFields.forEach((field) => {
    const input = form.elements[field];
    if (input) input.value = row[field] || "";
  });
  form.elements.application_status.value = row.application_status || "جديد";
  byId("cvFileInput").value = "";
  setFormMessage(isSupabaseEnabled() ? "" : "هذه معاينة محلية. الحفظ ورفع الملفات يحتاجان Supabase.", "");
  byId("fileList").innerHTML = isNew ? '<span class="muted">احفظ المتقدم أولًا ثم ارفع ملف CV.</span>' : '<span class="muted">تحميل الملفات...</span>';
  byId("applicantModal").classList.remove("hidden");
  byId("applicantModal").setAttribute("aria-hidden", "false");
  if (!isNew) loadApplicantFiles(row.id);
}

function closeApplicantModal() {
  byId("applicantModal").classList.add("hidden");
  byId("applicantModal").setAttribute("aria-hidden", "true");
  currentApplicant = null;
}

function collectApplicantPayload() {
  const form = byId("applicantForm");
  const payload = {};
  editableFields.forEach((field) => {
    const input = form.elements[field];
    if (!input) return;
    payload[field] = toDbValue(input.value);
  });
  payload.new_number = Number(payload.new_number);
  payload.graduation_year = payload.graduation_year ? Number(payload.graduation_year) : null;
  payload.application_status = payload.application_status || "جديد";
  return payload;
}

async function saveApplicant(event) {
  event.preventDefault();
  const client = getSupabaseClient();
  if (!client) {
    setFormMessage("الحفظ الحقيقي متاح بعد ربط Supabase.", "error");
    return;
  }

  const payload = collectApplicantPayload();
  if (!payload.full_name || !payload.main_category || !payload.sub_category || !payload.approved_specialty) {
    setFormMessage("الاسم والفئة الرئيسية والفئة الفرعية والتخصص المعتمد حقول مطلوبة.", "error");
    return;
  }

  setFormMessage("جاري حفظ البيانات...");
  let saved;
  if (currentApplicant?.id) {
    const { data, error } = await client
      .from("applicants")
      .update(payload)
      .eq("id", currentApplicant.id)
      .select("*")
      .single();
    if (error) {
      setFormMessage(`تعذر الحفظ: ${error.message}`, "error");
      return;
    }
    saved = data;
    state.applicants = state.applicants.map((row) => (row.id === saved.id ? saved : row));
  } else {
    const { data, error } = await client.from("applicants").insert(payload).select("*").single();
    if (error) {
      setFormMessage(`تعذر إضافة المتقدم: ${error.message}`, "error");
      return;
    }
    saved = data;
    state.applicants.push(saved);
  }

  currentApplicant = saved;
  byId("applicantId").value = saved.id;
  await uploadCvIfSelected(saved);
  refreshDerivedData();
  setFormMessage("تم حفظ البيانات بنجاح.", "success");
  byId("applicantModalTitle").textContent = saved.full_name;
  loadApplicantFiles(saved.id);
}

async function uploadCvIfSelected(applicant) {
  const fileInput = byId("cvFileInput");
  if (!fileInput.files.length) return;
  const client = getSupabaseClient();
  const file = fileInput.files[0];
  const safeName = file.name.replace(/[^\w.\-\u0600-\u06FF]+/g, "_");
  const path = `${applicant.id}/${Date.now()}_${safeName}`;
  const { error: uploadError } = await client.storage.from("applicant-files").upload(path, file, { upsert: false });
  if (uploadError) {
    setFormMessage(`تم حفظ البيانات لكن تعذر رفع الملف: ${uploadError.message}`, "error");
    return;
  }
  const { error: insertError } = await client.from("applicant_files").insert({
    applicant_id: applicant.id,
    file_type: "cv",
    file_name: file.name,
    file_path: path,
  });
  if (insertError) {
    setFormMessage(`تم رفع الملف لكن تعذر تسجيله: ${insertError.message}`, "error");
  }
  fileInput.value = "";
}

async function loadApplicantFiles(applicantId) {
  const client = getSupabaseClient();
  if (!client || !applicantId) {
    byId("fileList").innerHTML = '<span class="muted">لا توجد ملفات محفوظة.</span>';
    return;
  }
  const { data, error } = await client
    .from("applicant_files")
    .select("*")
    .eq("applicant_id", applicantId)
    .order("created_at", { ascending: false });
  if (error) {
    byId("fileList").innerHTML = `<span class="error-text">تعذر تحميل الملفات: ${escapeHtml(error.message)}</span>`;
    return;
  }
  if (!data || data.length === 0) {
    byId("fileList").innerHTML = '<span class="muted">لا توجد ملفات CV مرفوعة لهذا المتقدم.</span>';
    return;
  }

  const items = await Promise.all(
    data.map(async (file) => {
      const { data: signed } = await client.storage.from("applicant-files").createSignedUrl(file.file_path, 300);
      const href = signed?.signedUrl || "#";
      return `<div class="file-item"><span>${escapeHtml(file.file_name)}</span><a href="${href}" target="_blank" rel="noopener">فتح الملف</a></div>`;
    })
  );
  byId("fileList").innerHTML = items.join("");
}

async function loadData() {
  byId("dataStatus").textContent = "تحميل البيانات";
  const client = getSupabaseClient();
  if (client) {
    const allRows = [];
    const pageSize = 1000;
    for (let from = 0; ; from += pageSize) {
      const to = from + pageSize - 1;
      const { data, error } = await client
        .from("applicants")
        .select("*")
        .order("new_number", { ascending: true })
        .range(from, to);
      if (error) throw error;
      allRows.push(...(data || []));
      if (!data || data.length < pageSize) break;
    }
    state.applicants = allRows;
    state.missing = buildMissingRows(state.applicants);
    state.specialtyReview = buildSpecialtyReviewRows(state.applicants);
    state.mainSummary = buildMainSummary(state.applicants);
  } else {
    [state.applicants, state.missing, state.specialtyReview, state.mainSummary] = await Promise.all([
      loadCsv(DATA_PATHS.applicants),
      loadCsv(DATA_PATHS.missing),
      loadCsv(DATA_PATHS.specialtyReview),
      loadCsv(DATA_PATHS.mainSummary),
    ]);
  }
  state.filteredApplicants = state.applicants;
  byId("dataStatus").textContent = client ? "متصل بـ Supabase" : "البيانات المحلية جاهزة";
  setupFilters();
  renderDashboard();
  renderApplicantsTable();
  renderMissing();
  renderSpecialtyReview();
  renderReports();
}

function showApp() {
  byId("loginView").classList.add("hidden");
  byId("appView").classList.remove("hidden");
  loadData().catch(() => {
    byId("dataStatus").textContent = "تعذر تحميل البيانات";
  });
}

function setupAuth() {
  const client = getSupabaseClient();
  if (client) {
    client.auth.getSession().then(({ data }) => {
      if (data.session) showApp();
    });
  } else if (localStorage.getItem("hr_session") === "active") {
    showApp();
  }

  byId("loginForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const username = byId("username").value.trim();
    const password = byId("password").value;
    const activeClient = getSupabaseClient();

    if (activeClient) {
      byId("loginError").textContent = "";
      const { error } = await activeClient.auth.signInWithPassword({
        email: username,
        password,
      });
      if (!error) {
        showApp();
        return;
      }
      byId("loginError").textContent = "تعذر تسجيل الدخول. تأكد من البريد وكلمة المرور";
      return;
    }

    if (username === credentials.username && password === credentials.password) {
      localStorage.setItem("hr_session", "active");
      showApp();
      return;
    }
    byId("loginError").textContent = "اسم المستخدم أو كلمة المرور غير صحيحة";
  });

  byId("logoutBtn").addEventListener("click", async () => {
    const activeClient = getSupabaseClient();
    if (activeClient) await activeClient.auth.signOut();
    localStorage.removeItem("hr_session");
    location.reload();
  });
}

document.querySelectorAll(".nav-item").forEach((button) => {
  button.addEventListener("click", () => switchView(button.dataset.view));
});

byId("applicantsTable").addEventListener("click", (event) => {
  const button = event.target.closest("[data-open-applicant]");
  if (!button) return;
  const applicant = findApplicant(button.dataset.openApplicant);
  if (applicant) openApplicantModal(applicant);
});

byId("addApplicantBtn").addEventListener("click", () => openApplicantModal());
byId("closeApplicantModal").addEventListener("click", closeApplicantModal);
byId("cancelApplicantBtn").addEventListener("click", closeApplicantModal);
byId("applicantModal").addEventListener("click", (event) => {
  if (event.target.id === "applicantModal") closeApplicantModal();
});
byId("applicantForm").addEventListener("submit", saveApplicant);
byId("exportFiltered").addEventListener("click", exportFilteredApplicants);
byId("exportPdfBtn").addEventListener("click", exportPdf);
byId("exportXlsxBtn").addEventListener("click", exportXlsx);
setupAuth();
refreshIcons();
