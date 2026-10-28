param([ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '0.1.0')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
Set-Location $root
$bundle = "$PSScriptRoot\bundle"
if (Test-Path $bundle) { Remove-Item $bundle -Recurse -Force }
New-Item $bundle -ItemType Directory -Force | Out-Null
$env:PYTHONUTF8 = '1'
function Checked {
  param([string]$Program, [string[]]$Arguments)
  & $Program @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Build command failed: $Program" }
}
# All dependency installation happens on the build runner, never the client's PC.
Checked python @('-m','pip','install','-r','backend/requirements.txt','-r','packaging/windows/requirements-build.txt')
Push-Location frontend
try {
  Checked flutter @('config','--enable-windows-desktop')
  Checked flutter @('pub','get','--enforce-lockfile')
  Checked flutter @('build','windows','--release','--dart-define=DESKTOP_LOCAL_API=true','--dart-define=API_BASE_URL=http://127.0.0.1:18080')
} finally { Pop-Location }
$backendArguments = @('-m','PyInstaller','--noconfirm','--clean','--onedir','--name','AlHassanService',
  '--distpath',"$PSScriptRoot\dist",'--workpath',"$PSScriptRoot\build\service",'--specpath',$PSScriptRoot,
  '--paths',"$root\backend",'--collect-submodules','app','--collect-all','asyncpg',
  '--collect-submodules','livekit','--collect-submodules','uvicorn','--collect-all','greenlet','--collect-all','tzdata',
  '--hidden-import','sqlalchemy.dialects.postgresql.asyncpg',
  '--hidden-import','uvicorn.logging','--hidden-import','uvicorn.loops.asyncio',
  '--hidden-import','uvicorn.protocols.http.h11_impl','--hidden-import','uvicorn.protocols.websockets.websockets_impl',
  '--hidden-import','uvicorn.lifespan.on','--add-data',"$root\backend\alembic;alembic",'packaging/windows/service_entry.py')
Checked python $backendArguments
Checked python @('-m','PyInstaller','--noconfirm','--clean','--onedir','--windowed','--name','AlHassanLauncher',
  '--distpath',"$PSScriptRoot\dist",'--workpath',"$PSScriptRoot\build\launcher",'--specpath',$PSScriptRoot,
  '--paths',$PSScriptRoot,'packaging/windows/launcher.py')
Copy-Item "$PSScriptRoot\dist\AlHassanLauncher\*" $bundle -Recurse -Force
Copy-Item "$PSScriptRoot\dist\AlHassanService" "$bundle\service" -Recurse -Force
Copy-Item "$root\frontend\build\windows\x64\runner\Release" "$bundle\desktop" -Recurse -Force
$pg = 'C:\Program Files\PostgreSQL\17'
if (-not (Test-Path "$pg\bin\postgres.exe")) { throw 'PostgreSQL 17 build binaries are required on this build runner.' }
New-Item "$bundle\postgres" -ItemType Directory | Out-Null
foreach ($directory in @('bin','lib','share')) { Copy-Item "$pg\$directory" "$bundle\postgres\$directory" -Recurse -Force }
$pgVersion = (& "$pg\bin\postgres.exe" --version | Out-String).Trim()
if ($pgVersion -notmatch 'PostgreSQL\) 17\.') { throw 'Refusing to bundle a different PostgreSQL major version.' }
# App-local MSVC runtime: the client's machine does not need the development tools.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
$crt = Get-ChildItem "$vs\VC\Redist\MSVC" -Directory -Recurse | Where-Object {
  $_.Name -match '^Microsoft\.VC.*\.CRT$' -and $_.FullName -match '\\x64\\'
} | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $crt) { throw 'Could not find the redistributable x64 VC runtime.' }
foreach ($destination in @("$bundle\postgres\bin", "$bundle\desktop")) {
  Copy-Item "$($crt.FullName)\*.dll" $destination -Force
}
New-Item "$bundle\licenses" -ItemType Directory -Force | Out-Null
Copy-Item "$PSScriptRoot\licenses\*" "$bundle\licenses" -Recurse -Force
if (Test-Path "$pg\doc") { Copy-Item "$pg\doc" "$bundle\licenses\postgresql-doc" -Recurse -Force }
$pythonHome = Split-Path (Get-Command python).Source
if (Test-Path "$pythonHome\LICENSE.txt") { Copy-Item "$pythonHome\LICENSE.txt" "$bundle\licenses\Python.txt" }
python -m piplicenses --format=json --with-license-file --no-license-path --output-file="$bundle\licenses\python-packages.json"
if ($LASTEXITCODE -ne 0) { throw 'Could not generate bundled Python dependency notices.' }
$commit = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[a-f0-9]{40}$') { throw 'Build from a Git checkout with a valid revision.' }
@{ version = $Version; commit = $commit; postgresql = $pgVersion; architecture = 'windows-x64'; api_port = 18080 } |
  ConvertTo-Json | Set-Content "$bundle\build.json" -Encoding utf8
$manifest = Get-ChildItem $bundle -File -Recurse | ForEach-Object {
  @{ path = [IO.Path]::GetRelativePath($bundle, $_.FullName); sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower() }
}
$manifest | ConvertTo-Json | Set-Content "$bundle\files.sha256.json" -Encoding utf8
$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) { throw 'Inno Setup 6 is required on the build runner.' }
Checked $iscc @("/DAppVersion=$Version","$PSScriptRoot\installer.iss")
Get-ChildItem "$PSScriptRoot\output\*.exe" | ForEach-Object {
  $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
  "$hash  $($_.Name)" | Set-Content "$($_.FullName).sha256" -Encoding ascii
}
