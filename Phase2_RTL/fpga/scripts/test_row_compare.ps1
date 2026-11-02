param([string]$VivadoBin='C:/Xilinx/Vivado/2023.2/bin',[ValidateSet('mac','legacy')][string[]]$Kinds=@('mac','legacy'),[switch]$ReuseSnapshot)
$ErrorActionPreference='Stop'
$board=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$work=Join-Path $board 'work_row_compare'
$reports=Join-Path $board 'reports/row_gating_20261029/compare'
Push-Location $work
try {
  foreach($kind in $Kinds){
    $dir=Join-Path $reports $kind
    $testbench=if($kind -eq 'mac'){'tb_mac_row_compare.sv'}else{'legacy/tb_legacy_compare.sv'}
    $top=if($kind -eq 'mac'){'tb_mac_row_compare'}else{'tb_isolation'}
    $scope=if($kind -eq 'mac'){'tb_mac_row_compare/suite'}else{'tb_isolation/suite'}
    $glbl=Join-Path $VivadoBin '../data/verilog/src/glbl.v'
    if(!$ReuseSnapshot){
    & (Join-Path $VivadoBin 'xvlog.bat') -sv (Join-Path $dir 'timing.v') $testbench $glbl *> "$kind.compile.log"
    if($LASTEXITCODE){Get-Content "$kind.compile.log" -Tail 20;throw "$kind timing compile failed"}
    & (Join-Path $VivadoBin 'xelab.bat') -L simprims_ver -L unisims_ver -L secureip $top glbl -s "row_$kind" --O0 --mt 2 --debug typical --timescale 1ns/1ps -transport_int_delays -pulse_r 0 -pulse_int_r 0 -pulse_e 0 -pulse_int_e 0 *> "$kind.elaborate.log"
    }
    if($LASTEXITCODE -or (Select-String -LiteralPath "$kind.elaborate.log" -Pattern 'SDF backannotation was successful').Count -ne 1 -or (Select-String -LiteralPath "$kind.elaborate.log" -Quiet -Pattern 'ERROR:|WARNING:')){Get-Content "$kind.elaborate.log" -Tail 30;throw "$kind timing elaboration/annotation failed"}
    if($kind -eq 'legacy'){
      'run all','exit' | Set-Content -LiteralPath legacy_all.tcl
      & (Join-Path $VivadoBin 'xsim.bat') row_legacy --testplusarg CASE_4 -tclbatch legacy_all.tcl *> legacy_case4.log
      if($LASTEXITCODE -or !(Select-String -LiteralPath legacy_case4.log -Quiet -Pattern '^PASS isolation: jobs=64 checked_rows_across_variants=1280') -or (Select-String -LiteralPath legacy_case4.log -Quiet -Pattern 'Fatal:|Error:|[Tt]iming violation')){Get-Content legacy_case4.log -Tail 25;throw 'Original changing-weight case still fails'}
      & (Join-Path $VivadoBin 'xsim.bat') row_legacy -tclbatch legacy_all.tcl *> legacy_all.log
      if($LASTEXITCODE -or !(Select-String -LiteralPath legacy_all.log -Quiet -Pattern '^PASS isolation: jobs=653 checked_rows_across_variants=13060') -or (Select-String -LiteralPath legacy_all.log -Quiet -Pattern 'Fatal:|Error:|[Tt]iming violation')){Get-Content legacy_all.log -Tail 25;throw 'Legacy timing replay failed'}
      Select-String -LiteralPath legacy_all.log -Pattern '^PASS' | ForEach-Object {$_.Line}
    } else {
      foreach($profile in @('ACTUAL','DENSE','MASKS','IDLE')){
        $profileDir=Join-Path $dir $profile.ToLower()
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        $saif=(Join-Path $profileDir 'activity.saif').Replace('\','/')
        $activity=@"
set warmed 0
for {set i 0} {`$i < 256} {incr i} {
  run 40ns
  if {[get_value /tb_mac_row_compare/warmup_done] eq "1"} {set warmed 1; break}
}
if {!`$warmed} {error "MAC warm-up did not complete"}
open_saif {$saif}
log_saif [get_objects /tb_mac_row_compare/suite/*]
log_saif [get_objects /tb_mac_row_compare/suite/gated/*]
log_saif [get_objects /tb_mac_row_compare/suite/ungated/*]
run all
close_saif
exit
"@
        $tcl=(Join-Path $profileDir 'activity.tcl').Replace([char]92,[char]47)
        [IO.File]::WriteAllText($tcl,$activity)
        & (Join-Path $VivadoBin 'xsim.bat') row_mac --testplusarg $profile -tclbatch $tcl *> (Join-Path $profileDir 'run.log')
        if($LASTEXITCODE -or !(Select-String -LiteralPath (Join-Path $profileDir 'run.log') -Quiet -Pattern '^PASS MAC_ROW_COMPARE') -or (Select-String -LiteralPath (Join-Path $profileDir 'run.log') -Quiet -Pattern 'Fatal:|Error:|[Tt]iming violation')){Get-Content (Join-Path $profileDir 'run.log') -Tail 25;throw "MAC timing profile failed: $profile"}
        Select-String -LiteralPath (Join-Path $profileDir 'run.log') -Pattern '^PASS' | ForEach-Object {$_.Line}
      }
    }
    Copy-Item -LiteralPath "$kind.compile.log","$kind.elaborate.log" -Destination $dir
  }
} finally {Pop-Location}
