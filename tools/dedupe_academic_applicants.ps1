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

function Normalize-Id([string]$text) {
  if ([string]::IsNullOrWhiteSpace($text)) { return '' }
  return (($text.Trim() -replace '[^\d]', '')).Trim()
}

function Add-CsvBom([string]$path) {
  $content = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::UTF8)
  [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($true))
}

function Get-CompletenessScore($row) {
  $score = 0
  $fields = @(
    'full_name',
    'mobile',
    'phone',
    'national_id',
    'birth_date',
    'specialty_text',
    'suggested_specialty',
    'graduation_university',
    'graduation_year',
    'original_paper'
  )
  foreach ($field in $fields) {
    if (-not [string]::IsNullOrWhiteSpace([string]$row.$field)) { $score++ }
  }
  if (-not [string]::IsNullOrWhiteSpace([string]$row.mobile)) { $score += 2 }
  if (-not [string]::IsNullOrWhiteSpace([string]$row.national_id)) { $score += 3 }
  if (-not [string]::IsNullOrWhiteSpace([string]$row.graduation_university)) { $score += 2 }
  return $score
}

function Choose-BestRecord($rows) {
  return $rows |
    Sort-Object `
      @{ Expression = { Get-CompletenessScore $_ }; Descending = $true },
      @{ Expression = { if ([string]::IsNullOrWhiteSpace($_.issue_flags)) { 1 } else { 0 } }; Descending = $true },
      @{ Expression = { [int]$_.source_row }; Descending = $false } |
    Select-Object -First 1
}

function Get-MissingFields($row) {
  $missing = @()
  if ([string]::IsNullOrWhiteSpace($row.full_name)) { $missing += 'الاسم' }
  if ([string]::IsNullOrWhiteSpace($row.national_id)) { $missing += 'رقم الهوية' }
  if ([string]::IsNullOrWhiteSpace($row.mobile) -and [string]::IsNullOrWhiteSpace($row.phone)) { $missing += 'الهاتف/الجوال' }
  if ([string]::IsNullOrWhiteSpace($row.birth_date)) { $missing += 'تاريخ الميلاد' }
  if ([string]::IsNullOrWhiteSpace($row.specialty_text) -and [string]::IsNullOrWhiteSpace($row.suggested_specialty)) { $missing += 'التخصص' }
  if ([string]::IsNullOrWhiteSpace($row.graduation_university)) { $missing += 'جامعة التخرج' }
  if ([string]::IsNullOrWhiteSpace($row.graduation_year)) { $missing += 'سنة التخرج' }
  if ([string]::IsNullOrWhiteSpace($row.original_paper)) { $missing += 'الورقة الأصلية' }
  return $missing
}

$InputCsv = (Resolve-Path -LiteralPath $InputCsv).Path
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$rawRows = Import-Csv -LiteralPath $InputCsv
$nonApplicantRows = $rawRows | Where-Object { [string]::IsNullOrWhiteSpace($_.full_name) }
$rows = $rawRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.full_name) }
$prepared = foreach ($row in $rows) {
  $row | Add-Member -NotePropertyName normalized_name -NotePropertyValue (Normalize-Arabic $row.full_name) -Force
  $row | Add-Member -NotePropertyName normalized_id -NotePropertyValue (Normalize-Id $row.national_id) -Force
  $row | Add-Member -NotePropertyName completeness_score -NotePropertyValue (Get-CompletenessScore $row) -Force
  $row
}

$keptById = @()
$removed = @()

$idGroups = $prepared | Where-Object { $_.normalized_id -ne '' } | Group-Object normalized_id
foreach ($group in $idGroups) {
  if ($group.Count -eq 1) {
    $keptById += $group.Group[0]
    continue
  }

  $best = Choose-BestRecord $group.Group
  $keptById += $best
  foreach ($item in $group.Group) {
    if (-not [object]::ReferenceEquals($item, $best)) {
      $removed += [pscustomobject]@{
        duplicate_type = 'رقم هوية مكرر'
        duplicate_key = $group.Name
        removed_reason = 'تم اعتماد السجل الأكثر اكتمالا لنفس رقم الهوية'
        kept_source_sheet = $best.source_sheet
        kept_source_row = $best.source_row
        removed_source_sheet = $item.source_sheet
        removed_source_row = $item.source_row
        full_name = $item.full_name
        national_id = $item.national_id
        removed_score = $item.completeness_score
        kept_score = $best.completeness_score
      }
    }
  }
}

$keptById += $prepared | Where-Object { $_.normalized_id -eq '' }

$finalRows = @()
$nameGroups = $keptById | Where-Object { $_.normalized_name -ne '' } | Group-Object normalized_name
foreach ($group in $nameGroups) {
  if ($group.Count -eq 1) {
    $finalRows += $group.Group[0]
    continue
  }

  $best = Choose-BestRecord $group.Group
  $finalRows += $best
  foreach ($item in $group.Group) {
    if (-not [object]::ReferenceEquals($item, $best)) {
      $removed += [pscustomobject]@{
        duplicate_type = 'اسم مكرر'
        duplicate_key = $group.Name
        removed_reason = 'تم اعتماد السجل الأكثر اكتمالا لنفس الاسم'
        kept_source_sheet = $best.source_sheet
        kept_source_row = $best.source_row
        removed_source_sheet = $item.source_sheet
        removed_source_row = $item.source_row
        full_name = $item.full_name
        national_id = $item.national_id
        removed_score = $item.completeness_score
        kept_score = $best.completeness_score
      }
    }
  }
}

$finalRows += $keptById | Where-Object { $_.normalized_name -eq '' }

$ordered = $finalRows |
  Sort-Object suggested_specialty, full_name, source_sheet, @{ Expression = { [int]$_.source_row } }

$newNumber = 1
$finalOutput = foreach ($row in $ordered) {
  [pscustomobject]@{
    new_number = $newNumber++
    full_name = $row.full_name
    phone = $row.phone
    mobile = $row.mobile
    national_id = $row.national_id
    birth_date = $row.birth_date
    specialty_text = $row.specialty_text
    approved_specialty = $row.suggested_specialty
    specialty_review_status = $row.specialty_status
    graduation_university = $row.graduation_university
    graduation_year = $row.graduation_year
    original_paper = $row.original_paper
    source_sheet = $row.source_sheet
    source_row = $row.source_row
    issue_flags = $row.issue_flags
  }
}

$missingReport = foreach ($row in $finalOutput) {
  $missing = Get-MissingFields $row
  if ($missing.Count -gt 0) {
    [pscustomobject]@{
      new_number = $row.new_number
      full_name = $row.full_name
      national_id = $row.national_id
      approved_specialty = $row.approved_specialty
      missing_fields = ($missing -join '; ')
      missing_count = $missing.Count
      source_sheet = $row.source_sheet
      source_row = $row.source_row
    }
  }
}

$paths = @{
  final = Join-Path $OutputDir 'applicants_final_deduped.csv'
  removed = Join-Path $OutputDir 'removed_duplicate_rows.csv'
  nonApplicants = Join-Path $OutputDir 'non_applicant_rows_removed.csv'
  missing = Join-Path $OutputDir 'missing_data_report.csv'
  finalSummary = Join-Path $OutputDir 'final_summary_by_specialty.csv'
}

$finalOutput | Export-Csv -LiteralPath $paths.final -NoTypeInformation -Encoding UTF8
$removed | Export-Csv -LiteralPath $paths.removed -NoTypeInformation -Encoding UTF8
$nonApplicantRows | Export-Csv -LiteralPath $paths.nonApplicants -NoTypeInformation -Encoding UTF8
$missingReport | Sort-Object @{ Expression = { [int]$_.missing_count }; Descending = $true }, approved_specialty, full_name |
  Export-Csv -LiteralPath $paths.missing -NoTypeInformation -Encoding UTF8
$finalOutput | Group-Object approved_specialty | Sort-Object Count -Descending |
  ForEach-Object {
    [pscustomobject]@{
      specialty = $_.Name
      applicants = $_.Count
      rows_with_missing_data = @($_.Group | Where-Object {
        (Get-MissingFields $_).Count -gt 0
      }).Count
    }
  } | Export-Csv -LiteralPath $paths.finalSummary -NoTypeInformation -Encoding UTF8

foreach ($path in $paths.Values) { Add-CsvBom $path }

$remainingDuplicateIds = @($finalOutput |
  Where-Object { -not [string]::IsNullOrWhiteSpace($_.national_id) } |
  Group-Object national_id |
  Where-Object { $_.Count -gt 1 })

$remainingDuplicateNames = @($finalOutput |
  Where-Object { -not [string]::IsNullOrWhiteSpace($_.full_name) } |
  Group-Object full_name |
  Where-Object { $_.Count -gt 1 })

[pscustomobject]@{
  input_rows = $rawRows.Count
  non_applicant_rows_removed = @($nonApplicantRows).Count
  final_rows = @($finalOutput).Count
  removed_duplicate_rows = @($removed).Count
  missing_data_rows = @($missingReport).Count
  remaining_duplicate_id_groups = $remainingDuplicateIds.Count
  remaining_duplicate_name_groups = $remainingDuplicateNames.Count
  output_dir = (Resolve-Path -LiteralPath $OutputDir).Path
} | ConvertTo-Json -Depth 3
