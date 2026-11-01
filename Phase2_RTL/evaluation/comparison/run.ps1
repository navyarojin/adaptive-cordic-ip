param([Parameter(Mandatory=$true)][string]$Work,[ValidateSet('tb_banknote_model','tb_autonomous_model')][string]$Top='tb_banknote_model',[string]$VivadoBin='C:/Xilinx/Vivado/2023.2/bin')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$sources=@(Get-Content -LiteralPath (Join-Path $root 'rtl/sources.f') | Where-Object {$_.Trim()} | ForEach-Object {Join-Path $root $_})
$testFiles=@{tb_banknote_model="tb_model";tb_autonomous_model="tb_auto"}
$testFile=if($testFiles.ContainsKey($Top)){$testFiles[$Top]}else{$Top}
$sources+=Join-Path $root ("fpga/sim/"+$testFile+".sv")
Push-Location (Resolve-Path $Work)
try {
  & (Join-Path $VivadoBin 'xvlog.bat') -sv @sources *> model.compile.log
  if($LASTEXITCODE){Get-Content model.compile.log -Tail 25;throw 'Model compilation failed'}
  & (Join-Path $VivadoBin 'xelab.bat') $Top -s $Top --timescale 1ns/1ps *> model.elaborate.log
  if($LASTEXITCODE){Get-Content model.elaborate.log -Tail 25;throw 'Model elaboration failed'}
  & (Join-Path $VivadoBin 'xsim.bat') $Top -runall *> model.run.log
  if($LASTEXITCODE -or !(Select-String -LiteralPath model.run.log -Quiet -Pattern '^PASS (banknote|autonomous) model')) {
    Get-Content model.run.log -Tail 25;throw 'Model simulation failed'
  }
  Select-String -LiteralPath model.run.log -Pattern '^PASS|^MODEL_CYCLES' | ForEach-Object {$_.Line}
} finally {Pop-Location}
