param(
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$owner = 'copperstackTechnologies'
$repository = 'tandem-phone'
$expectedSigner = '8aef9af362cc4db72c42afc4b848b720e83ad5e8161cf12e2e3edaebeefcf4c4'
$projectRoot = $PSScriptRoot
$pubspec = Get-Content (Join-Path $projectRoot 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+\s*$') {
  throw 'pubspec.yaml must contain version: MAJOR.MINOR.PATCH+BUILD.'
}
$version = $Matches[1]
$tag = "v$version"
$sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$signer = Get-ChildItem (Join-Path $sdk 'build-tools') -Filter apksigner.bat -Recurse | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $signer) { throw "Could not find apksigner under $sdk" }

Push-Location $projectRoot
try {
  $remote = (& git remote get-url origin 2>$null).Trim()
  if ($remote -ne "https://github.com/$owner/$repository.git") {
    throw "Run this script from the $owner/$repository checkout. Current origin: $remote"
  }
  if (-not $SkipBuild) {
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Android release build failed.' }
  }
  $apkPath = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
  if (-not (Test-Path $apkPath)) { throw "Release APK not found: $apkPath" }
  $verification = & $signer verify --print-certs $apkPath 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed: $verification" }
  if ($verification -notmatch "(?i)Signer #1 certificate SHA-256 digest:\s*$expectedSigner") {
    throw 'The APK signing certificate does not match the installed Tandem Android signing identity. Refusing to publish an update users could not install.'
  }

  $dist = Join-Path $projectRoot 'dist'
  New-Item -ItemType Directory -Force $dist | Out-Null
  $apkName = "Tandem-Android-$version.apk"
  $publishedApk = Join-Path $dist $apkName
  Copy-Item $apkPath $publishedApk -Force
  $sha = (Get-FileHash $publishedApk -Algorithm SHA256).Hash.ToLowerInvariant()
  $downloadUrl = "https://github.com/$owner/$repository/releases/download/$tag/$apkName"
  $metadataPath = Join-Path $dist 'latest.json'
  $metadataJson = @{ version = $version; apkUrl = $downloadUrl; sha256 = $sha } | ConvertTo-Json -Compress
  [IO.File]::WriteAllText($metadataPath, $metadataJson, [Text.UTF8Encoding]::new($false))
  $checksumPath = Join-Path $dist "$apkName.sha256"
  "$sha  $apkName" | Set-Content -Path $checksumPath -Encoding ascii

  $credentialInput = "protocol=https`nhost=github.com`npath=$owner/$repository`n`n"
  $credentialLines = $credentialInput | & git credential fill 2>$null
  $credential = @{}
  foreach ($line in $credentialLines) {
    if ($line -match '^([^=]+)=(.*)$') { $credential[$Matches[1]] = $Matches[2] }
  }
  $token = $credential['password']
  if (-not $token) { throw 'No GitHub token is available from Git Credential Manager.' }

  $headers = @{
    Authorization = "Bearer $token"
    'User-Agent' = 'Tandem-Phone-Release'
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
  }
  $existingRelease = $false
  try {
    Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repository/releases/tags/$tag" -Headers $headers -ErrorAction Stop | Out-Null
    $existingRelease = $true
  } catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -ne 404) { throw }
  }
  if ($existingRelease) { throw "Release $tag already exists. Bump pubspec.yaml before publishing the next version." }

  $release = Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$owner/$repository/releases" `
    -Headers $headers -ContentType 'application/json' `
    -Body (@{ tag_name = $tag; target_commitish = 'main'; name = "Tandem Phone $tag"; body = "Android release $version. The APK is signed with Tandem's established Android signing identity."; draft = $false; prerelease = $false; make_latest = 'true' } | ConvertTo-Json)
  $uploadBase = $release.upload_url -replace '\{\?name,label\}$', ''
  foreach ($asset in @($publishedApk, $metadataPath, $checksumPath)) {
    $name = [Uri]::EscapeDataString([IO.Path]::GetFileName($asset))
    $mime = if ($asset -eq $publishedApk) { 'application/vnd.android.package-archive' } else { 'application/octet-stream' }
    Invoke-WebRequest -Method Post -Uri "$uploadBase`?name=$name" -Headers $headers -ContentType $mime -InFile $asset -TimeoutSec 1800 | Out-Null
  }
  $token = $null
  $headers = $null
  $credential = $null
  $credentialLines = $null
  Write-Output "Published $tag to https://github.com/$owner/$repository/releases/tag/$tag"
} finally {
  Pop-Location
}
