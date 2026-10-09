# Windows CI: install every repo type × assistant with -Os windows via install.ps1 and run the PowerShell tests.
#   pwsh tests/install-matrix.ps1
$root = Split-Path -Parent $PSScriptRoot
$fail = 0
foreach ($repo in (Get-ChildItem (Join-Path $root 'template/repo') -Directory).Name) {
 foreach ($assistant in (Get-ChildItem (Join-Path $root 'template/assistant') -Directory).Name) {
  Write-Output "=== repo=$repo os=windows assistant=$assistant cloud=aws"
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("factory-matrix-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Path $tmp | Out-Null
  Push-Location -LiteralPath $tmp
  try {
    git init -q -b main . ; git config user.email t@t ; git config user.name t
    Set-Content README.md '# scratch'; git add -A; git commit -qm init
    & pwsh -NoProfile -File (Join-Path $root 'install.ps1') $tmp -Repo $repo -Os windows -Assistant $assistant -Cloud aws | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'install failed' }
    if (& pwsh -NoProfile -File (Join-Path $root 'install.ps1') $tmp -Repo $repo -Os windows -Assistant $assistant -Cloud aws | Select-String '^added:') { throw 're-install added files' }
    git add -A; git commit -qm installed
    & pwsh -NoProfile -File scripts/factory/test-hooks.ps1; if ($LASTEXITCODE -ne 0) { throw 'test-hooks.ps1 failed' }
    & pwsh -NoProfile -File scripts/factory/check.ps1 *> $null; if ($LASTEXITCODE -ne 3) { throw 'check.ps1 should exit 3 with no checks' }
    (Get-Content scripts/factory/commands.env) -replace '^ALLOW_NO_CHECKS=0', 'ALLOW_NO_CHECKS=1' | Set-Content scripts/factory/commands.env
    & pwsh -NoProfile -File scripts/factory/setup.ps1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'setup.ps1 failed' }
    & pwsh -NoProfile -File scripts/factory/check.ps1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'check.ps1 failed' }
  } catch {
    Write-Output "FAILED: repo=$repo assistant=$assistant ($_)"; $fail = 1
  } finally {
    Pop-Location
    Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
  }
 }
}
if ($fail) { Write-Output 'install matrix (PowerShell): FAILED' } else { Write-Output 'install matrix (PowerShell): all passed' }
exit $fail
