# Test-Module.ps1
$ErrorActionPreference = 'Stop'

$moduleName = 'Koronet-Axerrio.GitTools'
$modulePath = Resolve-Path "$PSScriptRoot\Koronet-Axerrio.GitTools.psd1"

Write-Host ">>> Removing any loaded instance..." -ForegroundColor Cyan
Remove-Module $moduleName -ErrorAction SilentlyContinue

Write-Host ">>> Importing module..." -ForegroundColor Cyan
Import-Module $modulePath -Force -Verbose

$mod = Get-Module $moduleName
if (-not $mod) { Write-Error "Module failed to load!"; exit 1 }

Write-Host ">>> Exported functions:" -ForegroundColor Cyan
if ($mod.ExportedFunctions.Count -eq 0) {
  Write-Error "No functions were exported! Check FunctionsToExport in the psd1."
  exit 1
}
$mod.ExportedFunctions.Keys | ForEach-Object { " - $_" }

Write-Host ">>> Exported aliases:" -ForegroundColor Cyan
if ($mod.ExportedAliases.Count -eq 0) {
  Write-Host " (none)"
} else {
  $mod.ExportedAliases.Keys | ForEach-Object { " - $_" }
}

Write-Host ">>> Manifest validation:" -ForegroundColor Cyan
Test-ModuleManifest $modulePath | Out-String | Write-Host

Write-Host ">>> Quick help check for exported functions:" -ForegroundColor Cyan
foreach ($fn in $mod.ExportedFunctions.Keys) {
  Write-Host "`n--- $fn ---" -ForegroundColor Yellow
try {
    & $fn -? | Out-String | Write-Host
}
catch {
    Write-Warning ("Could not show help for {0}: {1}" -f $fn, $_)
}

}

Write-Host "`n>>> ShouldProcess / WhatIf capability scan:" -ForegroundColor Cyan
foreach ($fn in $mod.ExportedFunctions.Keys) {
  $cmd = Get-Command $fn -ErrorAction SilentlyContinue
  if (-not $cmd) { continue }

  # Does the function have WhatIf/Confirm parameters?
  $hasWhatIf  = $cmd.Parameters.ContainsKey('WhatIf')
  $hasConfirm = $cmd.Parameters.ContainsKey('Confirm')

  # Try to read ConfirmImpact from the CmdletBinding attribute (if present)
  $confirmImpact = $null
  try {
    $astAttr = $cmd.ScriptBlock.Ast.Attributes |
      Where-Object { $_.TypeName.GetReflectionType().FullName -eq 'System.Management.Automation.CmdletBindingAttribute' }
    if ($astAttr) {
      $ci = $astAttr.NamedArguments | Where-Object { $_.ArgumentName -eq 'ConfirmImpact' }
      if ($ci) { $confirmImpact = $ci.Argument.Extent.Text.Trim("'`"") }
    }
  } catch { }

  $status = if ($hasWhatIf) { "SupportsShouldProcess ✅" } else { "No ShouldProcess ⚠️" }
  $extra  = @()
  if ($hasConfirm)      { $extra += "Confirm" }
  if ($confirmImpact)   { $extra += "ConfirmImpact=$confirmImpact" }
  if ($extra.Count -gt 0) { $status += " (" + ($extra -join ", ") + ")" }

  Write-Host (" - {0}: {1}" -f $fn, $status)

  # Testcall using -WhatIf, ONLY if there are no mandatory params
  if ($hasWhatIf) {
    $mandatoryParams = @(
      $cmd.Parameters.Values | Where-Object { $_.Attributes |
        Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } }
    )
    if ($mandatoryParams.Count -eq 0) {
      try {
        Write-Host "   -> Dry run: & $fn -WhatIf" -ForegroundColor DarkGray
        & $fn -WhatIf | Out-String | Write-Host
      } catch {
        Write-Warning "   Could not invoke $fn -WhatIf: $_"
      }
    } else {
      Write-Host ("   -> Skipping -WhatIf dry run (mandatory params: {0})" -f (($mandatoryParams.Name) -join ", ")) -ForegroundColor DarkGray
    }
  }
}

Write-Host "`nAll checks done." -ForegroundColor Green
