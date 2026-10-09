# Generic audit logger for Copilot hook events (Windows / PowerShell 7+). Counterpart of log.sh.
# Usage (from .github/hooks/factory.json): pwsh -File log.ps1 <eventName>   (payload JSON on stdin)
# Never blocks the agent: always exits 0 and prints nothing.
param([string]$EventName = 'unknown')
try {
  . (Join-Path $PSScriptRoot 'common.ps1')
  $payloadJson = [Console]::In.ReadToEnd()
  Set-FactoryContext
  Write-FactoryLog $EventName $payloadJson
} catch { }
exit 0
