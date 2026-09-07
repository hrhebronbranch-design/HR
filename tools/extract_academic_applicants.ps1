param(
  [Parameter(Mandatory = $true)]
  [string]$WorkbookPath,

  [Parameter(Mandatory = $true)]
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

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

function Convert-ExcelDate([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return '' }
  $num = 0.0
  if ([double]::TryParse($value, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
    if ($num -gt 20000 -and $num -lt 60000) {
      return ([DateTime]::FromOADate($num).ToString('yyyy-MM-dd'))
    }
  }
  return $value.Trim()
}

function Convert-Year([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return '' }
  $v = $value.Trim()
  $num = 0.0
  if ([double]::TryParse($v, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
    if ($num -gt 1900 -and $num -lt 2100) { return ([int][Math]::Round($num)).ToString() }
  }
  return $v
}

function Column-Number([string]$cellRef) {
  $letters = ([regex]::Match($cellRef, '^[A-Z]+')).Value
  $n = 0
  foreach ($ch in $letters.ToCharArray()) {
    $n = ($n * 26) + ([int][char]$ch - 64)
  }
  return $n
}

function Get-SuggestedSpecialty([string]$specialtyText, [string]$sheetName, [string[]]$knownSpecialties) {
  $text = Normalize-Arabic $specialtyText
  $sheetNorm = Normalize-Arabic $sheetName
  if ($text -eq '') { return $sheetName }

  $rules = @(
    @{Name='هندسة حاسوب واتصالات'; Patterns=@('هندسه حاسوب','هندسه كمبيوتر','هندسه اتصالات','هندسه انظمه الحاسوب','هندسه نظم الحاسوب','اتصالات وحاسوب','حاسوب واتصالات')},
    @{Name='نظم معلومات'; Patterns=@('نظم معلومات','انظمه معلومات','نظم حاسوبيه','انظمه حاسوبيه','mis','نظم اداريه','نظم اداري')},
    @{Name='تكنولوجيا معلومات'; Patterns=@('تكنولوجيا معلومات','تكنولوجيا المعلومات','تقنيه معلومات','تقنيه المعلومات','تقنيات معلومات','امن معلومات')},
    @{Name='علم الحاسوب'; Patterns=@('علم الحاسوب','علوم حاسوب','علوم الكمبيوتر','كمبيوتر','حاسوب','برمجه','شبكات')},
    @{Name='هندسة مباني'; Patterns=@('هندسه مباني','هندسه مدنيه','مدني','معماري','عماره')},
    @{Name='إدارة أعمال'; Patterns=@('اداره اعمال','اداره الاعمال','اداره عامه','اداره')},
    @{Name='إدارة تربوية'; Patterns=@('اداره تربويه','اداره تعليميه','قياده تربويه')},
    @{Name='أساليب تدريس العلوم'; Patterns=@('اساليب تدريس العلوم','مناهج علوم','تدريس العلوم')},
    @{Name='أساليب تدريس عامة'; Patterns=@('اساليب تدريس','مناهج وطرق تدريس','طرق تدريس')},
    @{Name='إعلام'; Patterns=@('اعلام','صحافه','صحافه واعلام','علاقات عامه')},
    @{Name='اقتصاد'; Patterns=@('اقتصاد')},
    @{Name='بناء مؤسسات'; Patterns=@('بناء موسسات','تنميه موسسات','موسسات')},
    @{Name='تاريخ'; Patterns=@('تاريخ')},
    @{Name='علم النفس والإرشاد'; Patterns=@('علم نفس','ارشاد','ارشاد نفسي','ارشاد تربوي')},
    @{Name='تربية خاصة'; Patterns=@('تربيه خاصه')},
    @{Name='تربية رياضية'; Patterns=@('تربيه رياضيه','رياضه')},
    @{Name='تربية'; Patterns=@('تربيه','تعليم اساسي','معلم صف')},
    @{Name='ترجمة'; Patterns=@('ترجمه')},
    @{Name='تسويق'; Patterns=@('تسويق','ترويج')},
    @{Name='تغذية وتصنيع غذائي'; Patterns=@('تغذيه','تصنيع غذائي','علوم غذائيه')},
    @{Name='تمريض'; Patterns=@('تمريض')},
    @{Name='جغرافيا'; Patterns=@('جغرافيا')},
    @{Name='رياضيات'; Patterns=@('رياضيات','احصاء')},
    @{Name='زراعة'; Patterns=@('زراعه','انتاج نباتي','انتاج حيواني')},
    @{Name='شريعة'; Patterns=@('شريعه','فقه','اصول دين','دراسات اسلاميه')},
    @{Name='صيدلة'; Patterns=@('صيدله')},
    @{Name='طب بيطري'; Patterns=@('بيطري')},
    @{Name='طب وعلوم صحية'; Patterns=@('طب','علوم صحيه','صحه عامه','علاج طبيعي')},
    @{Name='علم اجتماع وخدمة اجتماعية'; Patterns=@('علم اجتماع','خدمه اجتماعيه','اجتماع')},
    @{Name='علم النفس والإرشاد'; Patterns=@('علم نفس','ارشاد','ارشاد نفسي','ارشاد تربوي')},
    @{Name='علوم بيئية'; Patterns=@('علوم بيئيه','بيئه')},
    @{Name='علوم سياسية'; Patterns=@('علوم سياسيه','سياسه')},
    @{Name='علوم طبية ومخبرية'; Patterns=@('علوم طبيه مخبريه','مختبرات طبيه','تحاليل طبيه','مخبريه')},
    @{Name='فنون'; Patterns=@('فنون','تصميم','تربيه فنيه')},
    @{Name='فيزياء'; Patterns=@('فيزياء')},
    @{Name='قانون'; Patterns=@('قانون','حقوق')},
    @{Name='كيمياء'; Patterns=@('كيمياء')},
    @{Name='لغة إنجليزية'; Patterns=@('لغه انجليزيه','انجليزي','english')},
    @{Name='لغة عربية'; Patterns=@('لغه عربيه','عربي')},
    @{Name='لغة فرنسية'; Patterns=@('لغه فرنسيه','فرنسي')},
    @{Name='مالية وتمويل'; Patterns=@('ماليه وتمويل','تمويل','علوم ماليه','مصارف')},
    @{Name='محاسبة'; Patterns=@('محاسبه')},
    @{Name='أحياء وعلوم حياتية'; Patterns=@('احياء','علوم حياتيه','بيولوجيا')}
  )

  foreach ($rule in $rules) {
    foreach ($pattern in $rule.Patterns) {
      if ($text.Contains((Normalize-Arabic $pattern))) { return $rule.Name }
    }
  }

  foreach ($known in $knownSpecialties) {
    if ($text.Contains((Normalize-Arabic $known)) -or (Normalize-Arabic $known).Contains($text)) {
      return $known
    }
  }

  return $sheetName
}

function Add-CsvBom([string]$path) {
  $content = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::UTF8)
  [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($true))
}

$WorkbookPath = (Resolve-Path -LiteralPath $WorkbookPath).Path
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$zip = [IO.Compression.ZipFile]::OpenRead($WorkbookPath)
try {
  function Read-EntryText([string]$path) {
    $entryPath = $path.TrimStart('/')
    $entry = $zip.GetEntry($entryPath)
    if (-not $entry) { return $null }
    $reader = [IO.StreamReader]::new($entry.Open())
    try { return $reader.ReadToEnd() } finally { $reader.Close() }
  }

  $sharedStrings = @()
  $sharedXmlText = Read-EntryText '/xl/sharedStrings.xml'
  if ($sharedXmlText) {
    [xml]$sharedXml = $sharedXmlText
    $sharedNs = [Xml.XmlNamespaceManager]::new($sharedXml.NameTable)
    $sharedNs.AddNamespace('d', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
    foreach ($si in $sharedXml.SelectNodes('//d:si', $sharedNs)) {
      $sharedStrings += (($si.SelectNodes('.//d:t', $sharedNs) | ForEach-Object { $_.'#text' }) -join '')
    }
  }

  function Get-CellText($cell) {
    if ($cell.t -eq 'inlineStr') {
      return (($cell.SelectNodes('.//*[local-name()="t"]') | ForEach-Object { $_.'#text' }) -join '')
    }
    if ($null -eq $cell.v) { return '' }
    $value = [string]$cell.v
    if ($cell.t -eq 's') {
      $idx = [int]$value
      if ($idx -ge 0 -and $idx -lt $sharedStrings.Count) { return $sharedStrings[$idx] }
    }
    return $value
  }

  [xml]$workbookXml = Read-EntryText '/xl/workbook.xml'
  [xml]$relsXml = Read-EntryText '/xl/_rels/workbook.xml.rels'
  $wbNs = [Xml.XmlNamespaceManager]::new($workbookXml.NameTable)
  $wbNs.AddNamespace('d', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')

  $relMap = @{}
  foreach ($rel in $relsXml.Relationships.Relationship) {
    $relMap[$rel.Id] = $rel.Target
  }

  $allSheets = @()
  foreach ($sheet in $workbookXml.SelectNodes('//d:sheets/d:sheet', $wbNs)) {
    $allSheets += [pscustomobject]@{
      Name = [string]$sheet.name
      RelId = $sheet.GetAttribute('id', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships')
      Target = $relMap[$sheet.GetAttribute('id', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships')]
    }
  }

  $sourceSheets = $allSheets | Where-Object { $_.Name -notin @('فهرس التخصصات', 'إحصاء') }
  $knownSpecialties = @($sourceSheets | ForEach-Object { $_.Name })

  $applicants = @()
  $issues = @()
  foreach ($sheet in $sourceSheets) {
    [xml]$sheetXml = Read-EntryText $sheet.Target
    $sheetNs = [Xml.XmlNamespaceManager]::new($sheetXml.NameTable)
    $sheetNs.AddNamespace('d', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
    $rows = $sheetXml.SelectNodes('//d:sheetData/d:row', $sheetNs)
    if ($rows.Count -lt 2) { continue }

    $headerRowNumber = 1
    foreach ($candidateHeader in $rows | Select-Object -First 12) {
      $headerText = @()
      foreach ($cell in $candidateHeader.SelectNodes('d:c', $sheetNs)) {
        $headerText += (Get-CellText $cell).Trim()
      }
      $joinedHeader = $headerText -join ' '
      if ($joinedHeader.Contains('الاسم') -and $joinedHeader.Contains('التخصص')) {
        $headerRowNumber = [int]$candidateHeader.r
        break
      }
    }

    foreach ($row in ($rows | Where-Object { [int]$_.r -gt $headerRowNumber })) {
      $cellsByCol = @{}
      foreach ($cell in $row.SelectNodes('d:c', $sheetNs)) {
        $col = Column-Number $cell.r
        $cellsByCol[$col] = (Get-CellText $cell).Trim()
      }

      $rowNumber = [int]$row.r
      $name = $cellsByCol[2]
      $nationalId = $cellsByCol[5]
      $specialtyText = $cellsByCol[7]
      if ((Normalize-Arabic $name) -eq 'الاسم' -or (Normalize-Arabic $specialtyText) -eq 'التخصص') {
        continue
      }
      if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($nationalId) -and [string]::IsNullOrWhiteSpace($specialtyText)) {
        continue
      }

      $suggested = Get-SuggestedSpecialty $specialtyText $sheet.Name $knownSpecialties
      $status = if ((Normalize-Arabic $suggested) -eq (Normalize-Arabic $sheet.Name)) { 'مطابق' } else { 'تخصص الشيت مختلف عن التخصص المقترح' }

      $flags = @()
      if ($status -ne 'مطابق') { $flags += 'تخصص_غير_مطابق' }
      if ([string]::IsNullOrWhiteSpace($nationalId)) { $flags += 'هوية_ناقصة' }
      if ([string]::IsNullOrWhiteSpace($cellsByCol[4]) -and [string]::IsNullOrWhiteSpace($cellsByCol[3])) { $flags += 'هاتف_ناقص' }
      $year = Convert-Year $cellsByCol[11]
      if ($year -ne '') {
        $yearNum = 0
        if (([int]::TryParse($year, [ref]$yearNum) -and ($yearNum -lt 1970 -or $yearNum -gt 2026)) -or -not [int]::TryParse($year, [ref]$yearNum)) {
          $flags += 'سنة_تخرج_تحتاج_مراجعة'
        }
      }

      $record = [pscustomobject]@{
        source_sheet = $sheet.Name
        source_row = $rowNumber
        source_number = $cellsByCol[1]
        full_name = $name
        phone = $cellsByCol[3]
        mobile = $cellsByCol[4]
        national_id = $nationalId
        birth_date = Convert-ExcelDate $cellsByCol[6]
        specialty_text = $specialtyText
        suggested_specialty = $suggested
        specialty_status = $status
        graduation_university = $cellsByCol[10]
        graduation_year = $year
        original_paper = $cellsByCol[12]
        issue_flags = ($flags -join ';')
      }
      $applicants += $record
      if ($flags.Count -gt 0) { $issues += $record }
    }
  }

  $duplicateIds = $applicants |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_.national_id) } |
    Group-Object national_id |
    Where-Object { $_.Count -gt 1 }

  $duplicateRows = foreach ($group in $duplicateIds) {
    foreach ($item in $group.Group) {
      [pscustomobject]@{
        national_id = $group.Name
        duplicate_count = $group.Count
        full_name = $item.full_name
        source_sheet = $item.source_sheet
        source_row = $item.source_row
        specialty_text = $item.specialty_text
        suggested_specialty = $item.suggested_specialty
      }
    }
  }

  $summary = $applicants |
    Group-Object suggested_specialty |
    Sort-Object Count -Descending |
    ForEach-Object {
      [pscustomobject]@{
        specialty = $_.Name
        applicants = $_.Count
        mismatched_sheet_rows = @($_.Group | Where-Object { $_.specialty_status -ne 'مطابق' }).Count
      }
    }

  $sheetSummary = $applicants |
    Group-Object source_sheet |
    Sort-Object Name |
    ForEach-Object {
      [pscustomobject]@{
        source_sheet = $_.Name
        rows = $_.Count
        rows_need_specialty_review = @($_.Group | Where-Object { $_.specialty_status -ne 'مطابق' }).Count
      }
    }

  $paths = @{
    applicants = Join-Path $OutputDir 'applicants_unified_cleaned.csv'
    review = Join-Path $OutputDir 'specialty_review_needed.csv'
    specialtyOnly = Join-Path $OutputDir 'specialty_mismatches_only.csv'
    duplicates = Join-Path $OutputDir 'duplicate_national_ids.csv'
    summary = Join-Path $OutputDir 'summary_by_suggested_specialty.csv'
    sheetSummary = Join-Path $OutputDir 'summary_by_source_sheet.csv'
  }

  $applicants | Export-Csv -LiteralPath $paths.applicants -NoTypeInformation -Encoding UTF8
  $issues | Export-Csv -LiteralPath $paths.review -NoTypeInformation -Encoding UTF8
  ($applicants | Where-Object { $_.specialty_status -ne 'مطابق' }) | Export-Csv -LiteralPath $paths.specialtyOnly -NoTypeInformation -Encoding UTF8
  $duplicateRows | Export-Csv -LiteralPath $paths.duplicates -NoTypeInformation -Encoding UTF8
  $summary | Export-Csv -LiteralPath $paths.summary -NoTypeInformation -Encoding UTF8
  $sheetSummary | Export-Csv -LiteralPath $paths.sheetSummary -NoTypeInformation -Encoding UTF8

  foreach ($path in $paths.Values) { Add-CsvBom $path }

  [pscustomobject]@{
    total_applicants = $applicants.Count
    specialty_review_needed = $issues.Count
    duplicate_national_id_rows = @($duplicateRows).Count
    output_dir = (Resolve-Path -LiteralPath $OutputDir).Path
  } | ConvertTo-Json -Depth 3
}
finally {
  $zip.Dispose()
}
