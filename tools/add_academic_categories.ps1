param(
  [Parameter(Mandatory = $true)]
  [string]$InputCsv,

  [Parameter(Mandatory = $true)]
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

function Normalize-Arabic([string]$text) {
  if ([string]::IsNullOrWhiteSpace($text)) { return '' }
  $t = $text.Trim()
  $t = $t -replace '[\u064B-\u065F\u0670\u0640]', ''
  $t = $t -replace '[إأآا]', 'ا'
  $t = $t -replace 'ى', 'ي'
  $t = $t -replace 'ؤ', 'و'
  $t = $t -replace 'ئ', 'ي'
  $t = $t -replace 'ة', 'ه'
  $t = $t -replace '\s+', ' '
  return $t.ToLowerInvariant()
}

function Add-CsvBom([string]$path) {
  $content = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::UTF8)
  [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($true))
}

function Get-Category($row) {
  $approved = Normalize-Arabic $row.approved_specialty
  $text = Normalize-Arabic (($row.specialty_text, $row.approved_specialty) -join ' ')

  # More specific rules first, so compound degrees land in the most useful category.
  if ($text -match 'اساليب|مناهج|طرق تدريس|تدريس') {
    return @{ Main = 'التربية والتعليم'; Sub = 'مناهج وأساليب تدريس' }
  }
  if ($text -match 'ارشاد|توجيه|علم نفس') {
    return @{ Main = 'العلوم الاجتماعية والإنسانية'; Sub = 'علم النفس والإرشاد' }
  }
  if ($text -match 'خدمه اجتماعيه|علم اجتماع|اجتماعيات|اجتماع') {
    return @{ Main = 'العلوم الاجتماعية والإنسانية'; Sub = 'علم الاجتماع والخدمة الاجتماعية' }
  }
  if ($text -match 'فقه|شريعه|اصول الدين|دراسات اسلاميه|تربيه اسلاميه') {
    return @{ Main = 'الشريعة والقانون'; Sub = 'الشريعة والدراسات الإسلامية' }
  }
  if ($text -match 'قانون|حقوق') {
    return @{ Main = 'الشريعة والقانون'; Sub = 'القانون والحقوق' }
  }
  if ($text -match 'محاسبه|تدقيق') {
    return @{ Main = 'الأعمال والاقتصاد'; Sub = 'المحاسبة والتدقيق' }
  }
  if ($text -match 'تمويل|ماليه|مصارف|علوم ماليه') {
    return @{ Main = 'الأعمال والاقتصاد'; Sub = 'المالية والتمويل' }
  }
  if ($text -match 'تسويق|ترويج') {
    return @{ Main = 'الأعمال والاقتصاد'; Sub = 'التسويق' }
  }
  if ($text -match 'اقتصاد') {
    return @{ Main = 'الأعمال والاقتصاد'; Sub = 'الاقتصاد' }
  }
  if ($text -match 'اداره|تجاره|اعمال|موسسات') {
    return @{ Main = 'الأعمال والاقتصاد'; Sub = 'الإدارة والأعمال' }
  }
  if ($text -match 'هندسه حاسوب|هندسه كمبيوتر|هندسه انظمه|هندسه نظم|اتصالات') {
    return @{ Main = 'الهندسة وتكنولوجيا المعلومات'; Sub = 'هندسة الحاسوب والاتصالات' }
  }
  if ($text -match 'نظم معلومات|انظمه معلومات|نظم حاسوبيه|انظمه حاسوبيه') {
    return @{ Main = 'الهندسة وتكنولوجيا المعلومات'; Sub = 'نظم المعلومات' }
  }
  if ($text -match 'تكنولوجيا معلومات|تقنيه معلومات|امن معلومات|حاسوب|كمبيوتر|برمجه|شبكات|علم الحاسوب') {
    return @{ Main = 'الهندسة وتكنولوجيا المعلومات'; Sub = 'علوم الحاسوب وتكنولوجيا المعلومات' }
  }
  if ($text -match 'هندسه مدنيه|هندسه مباني|معماري|عماره|ديكور') {
    return @{ Main = 'الهندسة وتكنولوجيا المعلومات'; Sub = 'الهندسة المدنية والمباني' }
  }
  if ($text -match 'هندسه كهربائيه') {
    return @{ Main = 'الهندسة وتكنولوجيا المعلومات'; Sub = 'الهندسة الكهربائية' }
  }
  if ($text -match 'هندسه كيميائيه') {
    return @{ Main = 'الهندسة وتكنولوجيا المعلومات'; Sub = 'الهندسة الكيميائية' }
  }
  if ($text -match 'طب مخبري|مختبر|تحاليل|مخبري') {
    return @{ Main = 'الصحة والعلوم الطبية'; Sub = 'العلوم الطبية والمخبرية' }
  }
  if ($text -match 'صيدله') {
    return @{ Main = 'الصحة والعلوم الطبية'; Sub = 'الصيدلة' }
  }
  if ($text -match 'تمريض') {
    return @{ Main = 'الصحة والعلوم الطبية'; Sub = 'التمريض' }
  }
  if ($text -match 'بيطري') {
    return @{ Main = 'الصحة والعلوم الطبية'; Sub = 'الطب البيطري' }
  }
  if ($text -match 'طب|صحه|علاج طبيعي') {
    return @{ Main = 'الصحة والعلوم الطبية'; Sub = 'الطب والعلوم الصحية' }
  }
  if ($text -match 'احياء|بيولوجيا|علوم حياتيه') {
    return @{ Main = 'العلوم الطبيعية والتطبيقية'; Sub = 'الأحياء والعلوم الحياتية' }
  }
  if ($text -match 'كيمياء') {
    return @{ Main = 'العلوم الطبيعية والتطبيقية'; Sub = 'الكيمياء' }
  }
  if ($text -match 'فيزياء') {
    return @{ Main = 'العلوم الطبيعية والتطبيقية'; Sub = 'الفيزياء' }
  }
  if ($text -match 'رياضيات|احصاء') {
    return @{ Main = 'العلوم الطبيعية والتطبيقية'; Sub = 'الرياضيات والإحصاء' }
  }
  if ($text -match 'ارض ومياه|مياه|وقايه النبات|انتاج ووقايه|تكنولوجيا زراعيه|تكنلوجيا زراعيه|علوم زراعيه') {
    return @{ Main = 'الزراعة والغذاء'; Sub = 'الزراعة والمياه والموارد الطبيعية' }
  }
  if ($approved -eq 'علوم بيييه') {
    return @{ Main = 'العلوم الطبيعية والتطبيقية'; Sub = 'العلوم البيئية' }
  }
  if ($text -match 'بيئه|بيئيه|بيييه|البيئه|البئيه|علوم بيئيه|علوم بيييه|هندسه تكنولوجيا البيئه|هندسه تكنولوجيا البيييه') {
    return @{ Main = 'العلوم الطبيعية والتطبيقية'; Sub = 'العلوم البيئية' }
  }
  if ($text -match 'زراعه|انتاج نباتي|انتاج حيواني|وقايه نبات') {
    return @{ Main = 'الزراعة والغذاء'; Sub = 'الزراعة والإنتاج النباتي والحيواني' }
  }
  if ($text -match 'تغذيه|تصنيع غذائي|علوم غذائيه') {
    return @{ Main = 'الزراعة والغذاء'; Sub = 'التغذية والتصنيع الغذائي' }
  }
  if ($text -match 'لغه انجليزيه|انجليزي|english|ادب انجليزي') {
    return @{ Main = 'اللغات والآداب'; Sub = 'اللغة الإنجليزية وآدابها' }
  }
  if ($text -match 'لغه عربيه|عربي|اللغة العربية|ادابها') {
    return @{ Main = 'اللغات والآداب'; Sub = 'اللغة العربية وآدابها' }
  }
  if ($text -match 'لغه فرنسيه|فرنسي') {
    return @{ Main = 'اللغات والآداب'; Sub = 'اللغة الفرنسية وآدابها' }
  }
  if ($text -match 'ترجمه') {
    return @{ Main = 'اللغات والآداب'; Sub = 'الترجمة' }
  }
  if ($text -match 'اعلام|صحافه|علاقات عامه') {
    return @{ Main = 'الإعلام والفنون'; Sub = 'الإعلام والاتصال' }
  }
  if ($text -match 'فنون|تصميم|تربيه فنيه') {
    return @{ Main = 'الإعلام والفنون'; Sub = 'الفنون والتصميم' }
  }
  if ($text -match 'تاريخ') {
    return @{ Main = 'العلوم الاجتماعية والإنسانية'; Sub = 'التاريخ' }
  }
  if ($text -match 'جغرافيا') {
    return @{ Main = 'العلوم الاجتماعية والإنسانية'; Sub = 'الجغرافيا' }
  }
  if ($text -match 'علوم سياسيه|سياسه') {
    return @{ Main = 'العلوم الاجتماعية والإنسانية'; Sub = 'العلوم السياسية' }
  }
  if ($text -match 'تربيه خاصه') {
    return @{ Main = 'التربية والتعليم'; Sub = 'التربية الخاصة' }
  }
  if ($text -match 'تربيه رياضيه|رياضه') {
    return @{ Main = 'التربية والتعليم'; Sub = 'التربية الرياضية' }
  }
  if ($text -match 'تربيه|تعليم اساسي|معلم صف') {
    return @{ Main = 'التربية والتعليم'; Sub = 'التربية العامة والتعليم الأساسي' }
  }

  switch ($approved) {
    'اداره اعمال' { return @{ Main = 'الأعمال والاقتصاد'; Sub = 'الإدارة والأعمال' } }
    'بناء موسسات' { return @{ Main = 'الأعمال والاقتصاد'; Sub = 'الإدارة والأعمال' } }
    'اداره تربويه' { return @{ Main = 'التربية والتعليم'; Sub = 'الإدارة التربوية' } }
    'تربيه' { return @{ Main = 'التربية والتعليم'; Sub = 'التربية العامة والتعليم الأساسي' } }
    default { return @{ Main = 'غير مصنف'; Sub = 'يحتاج مراجعة' } }
  }
}

$InputCsv = (Resolve-Path -LiteralPath $InputCsv).Path
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$rows = Import-Csv -LiteralPath $InputCsv

$categorized = foreach ($row in $rows) {
  $cat = Get-Category $row
  [pscustomobject]@{
    new_number = $row.new_number
    full_name = $row.full_name
    phone = $row.phone
    mobile = $row.mobile
    national_id = $row.national_id
    birth_date = $row.birth_date
    main_category = $cat.Main
    sub_category = $cat.Sub
    specialty_text = $row.specialty_text
    approved_specialty = $row.approved_specialty
    specialty_review_status = $row.specialty_review_status
    graduation_university = $row.graduation_university
    graduation_year = $row.graduation_year
    original_paper = $row.original_paper
    source_sheet = $row.source_sheet
    source_row = $row.source_row
    issue_flags = $row.issue_flags
  }
}

$categoryMap = $categorized |
  Group-Object approved_specialty, main_category, sub_category |
  Sort-Object Name |
  ForEach-Object {
    $parts = $_.Name -split ', '
    [pscustomobject]@{
      approved_specialty = $parts[0]
      main_category = $parts[1]
      sub_category = $parts[2]
      applicants = $_.Count
    }
  }

$categorySummary = $categorized |
  Group-Object main_category, sub_category |
  Sort-Object Count -Descending |
  ForEach-Object {
    $parts = $_.Name -split ', '
    [pscustomobject]@{
      main_category = $parts[0]
      sub_category = $parts[1]
      applicants = $_.Count
    }
  }

$mainSummary = $categorized |
  Group-Object main_category |
  Sort-Object Count -Descending |
  ForEach-Object {
    [pscustomobject]@{
      main_category = $_.Name
      applicants = $_.Count
      sub_categories = @($_.Group | Group-Object sub_category).Count
    }
  }

$uncategorized = $categorized | Where-Object { $_.main_category -eq 'غير مصنف' }

$paths = @{
  final = Join-Path $OutputDir 'applicants_final_categorized.csv'
  map = Join-Path $OutputDir 'specialty_category_map.csv'
  summary = Join-Path $OutputDir 'summary_by_category.csv'
  mainSummary = Join-Path $OutputDir 'summary_by_main_category.csv'
  uncategorized = Join-Path $OutputDir 'uncategorized_review.csv'
}

$categorized | Export-Csv -LiteralPath $paths.final -NoTypeInformation -Encoding UTF8
$categoryMap | Export-Csv -LiteralPath $paths.map -NoTypeInformation -Encoding UTF8
$categorySummary | Export-Csv -LiteralPath $paths.summary -NoTypeInformation -Encoding UTF8
$mainSummary | Export-Csv -LiteralPath $paths.mainSummary -NoTypeInformation -Encoding UTF8
$uncategorized | Export-Csv -LiteralPath $paths.uncategorized -NoTypeInformation -Encoding UTF8

foreach ($path in $paths.Values) { Add-CsvBom $path }

[pscustomobject]@{
  input_rows = $rows.Count
  output_rows = @($categorized).Count
  main_categories = @($mainSummary).Count
  sub_categories = @($categorySummary).Count
  uncategorized_rows = @($uncategorized).Count
  output_dir = (Resolve-Path -LiteralPath $OutputDir).Path
} | ConvertTo-Json -Depth 3
