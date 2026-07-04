# Downloads IPA phoneme recordings from Wikimedia Commons
# Uses curl.exe (built into Windows 10+) with retry and rate limiting.
# Run from the project root: .\scripts\download_ipa_audio.ps1

$dest = Join-Path $PSScriptRoot "..\assets\audio\ipa"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$files = @(
  @{ name = "PR-open_front_unrounded_vowel.ogg";          url = "https://upload.wikimedia.org/wikipedia/commons/0/0e/PR-open_front_unrounded_vowel.ogg" },
  @{ name = "Close_front_unrounded_vowel.ogg";             url = "https://upload.wikimedia.org/wikipedia/commons/9/91/Close_front_unrounded_vowel.ogg" },
  @{ name = "Close_back_rounded_vowel.ogg";                url = "https://upload.wikimedia.org/wikipedia/commons/5/5d/Close_back_rounded_vowel.ogg" },
  @{ name = "Close-mid_back_rounded_vowel.ogg";            url = "https://upload.wikimedia.org/wikipedia/commons/8/84/Close-mid_back_rounded_vowel.ogg" },
  @{ name = "Close-mid_front_unrounded_vowel.ogg";         url = "https://upload.wikimedia.org/wikipedia/commons/6/6c/Close-mid_front_unrounded_vowel.ogg" },
  @{ name = "Close_central_unrounded_vowel.ogg";           url = "https://upload.wikimedia.org/wikipedia/commons/5/53/Close_central_unrounded_vowel.ogg" },
  @{ name = "Voiced_bilabial_plosive.ogg";                 url = "https://upload.wikimedia.org/wikipedia/commons/2/2c/Voiced_bilabial_plosive.ogg" },
  @{ name = "Voiceless_bilabial_plosive.ogg";              url = "https://upload.wikimedia.org/wikipedia/commons/5/51/Voiceless_bilabial_plosive.ogg" },
  @{ name = "Voiced_alveolar_plosive.ogg";                 url = "https://upload.wikimedia.org/wikipedia/commons/0/01/Voiced_alveolar_plosive.ogg" },
  @{ name = "Voiceless_alveolar_plosive.ogg";              url = "https://upload.wikimedia.org/wikipedia/commons/0/02/Voiceless_alveolar_plosive.ogg" },
  @{ name = "Voiced_velar_plosive_02.ogg";                 url = "https://upload.wikimedia.org/wikipedia/commons/1/12/Voiced_velar_plosive_02.ogg" },
  @{ name = "Voiceless_velar_plosive.ogg";                 url = "https://upload.wikimedia.org/wikipedia/commons/e/e3/Voiceless_velar_plosive.ogg" },
  @{ name = "Bilabial_nasal.ogg";                          url = "https://upload.wikimedia.org/wikipedia/commons/a/a9/Bilabial_nasal.ogg" },
  @{ name = "Alveolar_nasal.ogg";                          url = "https://upload.wikimedia.org/wikipedia/commons/2/29/Alveolar_nasal.ogg" },
  @{ name = "Palatal_nasal.ogg";                           url = "https://upload.wikimedia.org/wikipedia/commons/4/46/Palatal_nasal.ogg" },
  @{ name = "Voiced_labio-dental_fricative.ogg";           url = "https://upload.wikimedia.org/wikipedia/commons/4/42/Voiced_labio-dental_fricative.ogg" },
  @{ name = "Voiceless_labio-dental_fricative.ogg";        url = "https://upload.wikimedia.org/wikipedia/commons/c/c7/Voiceless_labio-dental_fricative.ogg" },
  @{ name = "Voiced_alveolar_sibilant.ogg";                url = "https://upload.wikimedia.org/wikipedia/commons/c/c0/Voiced_alveolar_sibilant.ogg" },
  @{ name = "Voiceless_alveolar_sibilant.ogg";             url = "https://upload.wikimedia.org/wikipedia/commons/a/ac/Voiceless_alveolar_sibilant.ogg" },
  @{ name = "Voiced_retroflex_sibilant.ogg";               url = "https://upload.wikimedia.org/wikipedia/commons/7/7f/Voiced_retroflex_sibilant.ogg" },
  @{ name = "Voiceless_retroflex_sibilant.ogg";            url = "https://upload.wikimedia.org/wikipedia/commons/b/b1/Voiceless_retroflex_sibilant.ogg" },
  @{ name = "Voiceless_alveolo-palatal_sibilant.ogg";      url = "https://upload.wikimedia.org/wikipedia/commons/0/0b/Voiceless_alveolo-palatal_sibilant.ogg" },
  @{ name = "Voiceless_velar_fricative.ogg";               url = "https://upload.wikimedia.org/wikipedia/commons/0/0f/Voiceless_velar_fricative.ogg" },
  @{ name = "Voiced_velar_fricative.ogg";                  url = "https://upload.wikimedia.org/wikipedia/commons/4/47/Voiced_velar_fricative.ogg" },
  @{ name = "Voiced_dental_fricative.ogg";                 url = "https://upload.wikimedia.org/wikipedia/commons/6/6a/Voiced_dental_fricative.ogg" },
  @{ name = "Voiceless_dental_fricative.ogg";              url = "https://upload.wikimedia.org/wikipedia/commons/8/80/Voiceless_dental_fricative.ogg" },
  @{ name = "Voiced_glottal_fricative.ogg";                url = "https://upload.wikimedia.org/wikipedia/commons/e/e2/Voiced_glottal_fricative.ogg" },
  @{ name = "Voiceless_alveolar_sibilant_affricate.oga";   url = "https://upload.wikimedia.org/wikipedia/commons/9/9d/Voiceless_alveolar_sibilant_affricate.oga" },
  @{ name = "Voiceless_alveolo-palatal_affricate.ogg";     url = "https://upload.wikimedia.org/wikipedia/commons/c/c4/Voiceless_alveolo-palatal_affricate.ogg" },
  @{ name = "Palatal_approximant.ogg";                     url = "https://upload.wikimedia.org/wikipedia/commons/e/e8/Palatal_approximant.ogg" },
  @{ name = "Alveolar_lateral_approximant.ogg";            url = "https://upload.wikimedia.org/wikipedia/commons/b/bc/Alveolar_lateral_approximant.ogg" },
  @{ name = "Alveolar_trill.ogg";                          url = "https://upload.wikimedia.org/wikipedia/commons/c/ce/Alveolar_trill.ogg" }
)

$curlExe = "curl.exe"
$ok = 0; $skip = 0; $fail = 0

foreach ($f in $files) {
  $path = Join-Path $dest $f.name
  if (Test-Path $path) {
    Write-Host "SKIP  $($f.name)" -ForegroundColor DarkGray
    $skip++
    continue
  }

  # curl: --retry 4 retries on 429/5xx, --retry-delay 15s between retries
  # --limit-rate 50k throttles transfer to avoid triggering CDN limits
  & $curlExe --silent --show-error --location `
    --retry 4 --retry-delay 15 --retry-all-errors `
    --limit-rate 50k `
    --user-agent "Mozilla/5.0 (compatible; TalutaluApp/1.0)" `
    --output $path `
    $f.url

  if ($LASTEXITCODE -eq 0 -and (Test-Path $path) -and (Get-Item $path).Length -gt 1000) {
    Write-Host "OK    $($f.name)" -ForegroundColor Green
    $ok++
  } else {
    if (Test-Path $path) { Remove-Item $path -Force }
    Write-Host "FAIL  $($f.name)" -ForegroundColor Red
    $fail++
  }

  Start-Sleep -Seconds 3
}

Write-Host ""
Write-Host "Done: $ok downloaded, $skip skipped, $fail failed."
