param([Parameter(Mandatory=$true)][string]$Work,[string]$VivadoBin='C:/Xilinx/Vivado/2023.2/bin')
$ErrorActionPreference='Stop'
Push-Location (Resolve-Path -LiteralPath $Work)
try {
  & (Join-Path $VivadoBin 'xvlog.bat') -sv legacy.sv plain.sv retained.sv zero_hold.sv zero_dual_hold.sv tb_isolation.sv *> compile.log
  if($LASTEXITCODE){Get-Content compile.log -Tail 25;throw 'Isolation compile failed'}
  & (Join-Path $VivadoBin 'xelab.bat') tb_isolation -s isolation --debug typical --timescale 1ns/1ps *> elaborate.log
  if($LASTEXITCODE){Get-Content elaborate.log -Tail 25;throw 'Isolation elaboration failed'}
  & (Join-Path $VivadoBin 'xsim.bat') isolation -tclbatch all.tcl *> run.log
  if($LASTEXITCODE -or !(Select-String -LiteralPath run.log -Quiet -Pattern '^PASS isolation:') -or (Select-String -LiteralPath run.log -Quiet -Pattern 'Fatal:|Error:')){Get-Content run.log -Tail 35;throw 'Isolation comparison failed'}
  Select-String -LiteralPath run.log -Pattern '^SWITCH|^PASS' | ForEach-Object {$_.Line}
  foreach($case in 0..7){
    & (Join-Path $VivadoBin 'xsim.bat') isolation --testplusarg "CASE_$case" -tclbatch "case_$case/activity.tcl" *> "case_$case/run.log"
    if($LASTEXITCODE -or !(Select-String -LiteralPath "case_$case/run.log" -Quiet -Pattern '^PASS isolation:') -or (Select-String -LiteralPath "case_$case/run.log" -Quiet -Pattern 'Fatal:|Error:')){Get-Content "case_$case/run.log" -Tail 30;throw "Activity case failed: $case"}
  }
  foreach($sizeTest in @('tb_hold_sizes','tb_dual_sizes')){
    & (Join-Path $VivadoBin 'xvlog.bat') -sv "$sizeTest.sv" *> "$sizeTest.compile.log"
    if($LASTEXITCODE){throw "Size-test compile failed: $sizeTest"}
    & (Join-Path $VivadoBin 'xelab.bat') $sizeTest -s $sizeTest --debug typical --timescale 1ns/1ps *> "$sizeTest.elaborate.log"
    if($LASTEXITCODE){throw "Size-test elaboration failed: $sizeTest"}
    & (Join-Path $VivadoBin 'xsim.bat') $sizeTest -runall *> "$sizeTest.run.log"
    if($LASTEXITCODE -or !(Select-String -LiteralPath "$sizeTest.run.log" -Quiet -Pattern '^PASS parameterized systolic arrays:') -or (Select-String -LiteralPath "$sizeTest.run.log" -Quiet -Pattern 'Fatal:|Error:')){throw "Size-test regression failed: $sizeTest"}
    Select-String -LiteralPath "$sizeTest.run.log" -Pattern '^PASS' | ForEach-Object {$_.Line}
  }
}finally{Pop-Location}
