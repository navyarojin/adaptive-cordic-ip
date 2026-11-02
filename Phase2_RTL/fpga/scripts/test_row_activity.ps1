param([string]$VivadoBin='C:/Xilinx/Vivado/2023.2/bin',[switch]$ReuseSnapshot)
$ErrorActionPreference='Stop'
$board=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$work=Join-Path $board 'work_row_compare'
$reports=Join-Path $board 'reports/row_gating_20261029/compare/mac'
Push-Location $work
try {
  if(!$ReuseSnapshot){
    Copy-Item (Join-Path $board 'experiments/tb_mac_row_compare.sv') 'tb_mac_row_compare.sv'
    & (Join-Path $VivadoBin 'xvlog.bat') -sv -d RTL_ACTIVITY (Join-Path $board '../rtl/mac.sv') mac_row_compare.sv tb_mac_row_compare.sv (Join-Path $VivadoBin '../data/verilog/src/glbl.v') *> rtl_activity_compile.log
    if($LASTEXITCODE){Get-Content rtl_activity_compile.log -Tail 15;throw 'RTL activity compile failed'}
    & (Join-Path $VivadoBin 'xelab.bat') -L unisims_ver -L secureip tb_mac_row_compare glbl -s row_mac_rtl_activity --mt 2 --debug typical --timescale 1ns/1ps *> rtl_activity_elaborate.log
    if($LASTEXITCODE){Get-Content rtl_activity_elaborate.log -Tail 15;throw 'RTL activity elaboration failed'}
  }
  foreach($profile in @('ACTUAL','DENSE','MASKS','IDLE')){
    $dir=Join-Path $reports ('rtl_'+$profile.ToLower())
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $saif=(Join-Path $dir 'activity.saif').Replace([char]92,[char]47)
    $tcl=(Join-Path $dir 'activity.tcl').Replace([char]92,[char]47)
    $body=@"
set warmed 0
for {set i 0} {`$i < 256} {incr i} {
  run 40ns
  if {[get_value /tb_mac_row_compare/warmup_done] eq "1"} {set warmed 1; break}
}
if {!`$warmed} {error "Warm-up incomplete"}
open_saif {$saif}
log_saif [get_objects -r /tb_mac_row_compare/suite/*]
run all
close_saif
exit
"@
    [IO.File]::WriteAllText($tcl,$body)
    & (Join-Path $VivadoBin 'xsim.bat') row_mac_rtl_activity --testplusarg $profile -tclbatch $tcl *> (Join-Path $dir 'run.log')
    if($LASTEXITCODE -or !(Select-String -LiteralPath (Join-Path $dir 'run.log') -Quiet -Pattern '^PASS MAC_ROW_COMPARE') -or (Select-String -LiteralPath (Join-Path $dir 'run.log') -Quiet -Pattern 'Fatal:|Error:')){Get-Content (Join-Path $dir 'run.log') -Tail 25;throw "RTL activity profile failed: $profile"}
    Select-String -LiteralPath (Join-Path $dir 'run.log') -Pattern '^PASS|^SWITCH_ROW' | ForEach-Object {$_.Line}
  }
  Copy-Item rtl_activity_compile.log,rtl_activity_elaborate.log $reports
} finally {Pop-Location}
