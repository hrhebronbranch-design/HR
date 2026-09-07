const DATA_PATHS = {
  applicants: "./data/applicants_final_categorized.csv",
  missing: "./data/missing_data_report.csv",
  specialtyReview: "./data/specialty_mismatches_only.csv",
  mainSummary: "./data/summary_by_main_category.csv",
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
      const status = hasMissing(row)
        ? '<span class="badge warn">ناقص</span>'
        : '<span class="badge ok">مكتمل</span>';
      return `
        <tr>
          <td>${row.new_number}</td>
          <td>${row.full_name}</td>
          <td>${row.national_id || ""}</td>
          <td>${row.mobile || row.phone || ""}</td>
          <td>${row.main_category}</td>
          <td>${row.sub_category}</td>
          <td>${row.approved_specialty}</td>
          <td>${row.graduation_university || ""}</td>
          <td>${row.graduation_year || ""}</td>
          <td>${status}</td>
        </tr>
      `;
    })
    .join("");
}

function renderMissing() {
  byId("missingCount").textContent = `${state.missing.length.toLocaleString("ar")} سجل`;
  byId("missingTable").innerHTML = state.missing
    .slice(0, 500)
    .map(
      (row) => `
        <tr>
          <td>${row.new_number}</td>
          <td>${row.full_name}</td>
          <td>${row.national_id || ""}</td>
          <td>${row.approved_specialty}</td>
          <td>${row.missing_fields}</td>
          <td>${row.source_sheet} / ${row.source_row}</td>
        </tr>
      `
    )
    .join("");
}

function renderSpecialtyReview() {
  byId("specialtyReviewCount").textContent = `${state.specialtyReview.length.toLocaleString("ar")} سجل`;
  byId("specialtyReviewTable").innerHTML = state.specialtyReview
    .slice(0, 500)
    .map(
      (row) => `
        <tr>
          <td>${row.source_sheet}</td>
          <td>${row.source_row}</td>
          <td>${row.full_name}</td>
          <td>${row.specialty_text}</td>
          <td>${row.suggested_specialty}</td>
        </tr>
      `
    )
    .join("");
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
}

function setupFilters() {
  fillSelect(byId("mainCategoryFilter"), "كل الفئات الرئيسية", uniqueValues(state.applicants, "main_category"));
  fillSelect(byId("subCategoryFilter"), "كل الفئات الفرعية", uniqueValues(state.applicants, "sub_category"));
  fillSelect(byId("specialtyFilter"), "كل التخصصات", uniqueValues(state.applicants, "approved_specialty"));
  ["searchInput", "mainCategoryFilter", "subCategoryFilter", "specialtyFilter", "missingFilter"].forEach((id) => {
    byId(id).addEventListener("input", applyApplicantFilters);
    byId(id).addEventListener("change", applyApplicantFilters);
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

async function loadData() {
  byId("dataStatus").textContent = "تحميل البيانات";
  const client = getSupabaseClient();
  if (client) {
    const { data, error } = await client
      .from("applicants")
      .select("*")
      .order("new_number", { ascending: true });
    if (error) throw error;
    state.applicants = data || [];
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

byId("exportFiltered").addEventListener("click", exportFilteredApplicants);
setupAuth();

