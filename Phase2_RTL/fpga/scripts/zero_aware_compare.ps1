param([Parameter(Mandatory=$true)][string]$Work,[string]$VivadoBin='C:/Xilinx/Vivado/2023.2/bin')
$ErrorActionPreference='Stop'
Push-Location (Resolve-Path $Work)
try {
  & (Join-Path $VivadoBin 'xvlog.bat') -sv gated.sv ungated.sv tb_zero_aware.sv *> compile.log
  if($LASTEXITCODE){throw 'Gating comparison compile failed'}
  & (Join-Path $VivadoBin 'xelab.bat') tb_zero_aware -s tb_zero_aware --debug typical --timescale 1ns/1ps *> elaborate.log
  if($LASTEXITCODE){Get-Content elaborate.log -Tail 20;throw 'Gating comparison elaborate failed'}
  & (Join-Path $VivadoBin 'xsim.bat') tb_zero_aware -tclbatch activity.tcl *> run.log
  if($LASTEXITCODE -or !(Select-String -LiteralPath run.log -Quiet -Pattern '^PASS zero-aware baseline') -or (Select-String -LiteralPath run.log -Quiet -Pattern 'Fatal:|Error:')) {Get-Content run.log -Tail 25;throw 'Gating comparison failed'}
  Select-String -LiteralPath run.log -Pattern '^SWITCHING|^PASS' | ForEach-Object {$_.Line}
} finally {Pop-Location}
