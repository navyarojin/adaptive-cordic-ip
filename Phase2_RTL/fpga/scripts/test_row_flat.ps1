param([string]$VivadoBin='C:/Xilinx/Vivado/2023.2/bin',[ValidateSet('mac','legacy')][string[]]$Kinds=@('mac','legacy'),[switch]$ReuseSnapshot,[switch]$CarryPortAliases)
$ErrorActionPreference='Stop'
$board=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$work=Join-Path $board 'work_row_flat'
$reports=Join-Path $board 'reports/row_gating_20261029/flat_compare'
Push-Location $work
try {
  @('run all','exit') | Set-Content run_all.tcl
  foreach($kind in $Kinds){
    $dir=Join-Path $reports $kind
    $snapshot="flat_$kind"
    if($CarryPortAliases -and $kind -eq 'legacy'){
      $original=$dir
      $dir=Join-Path $dir 'bus_ports'
      $snapshot='flat_legacy_bus_ports'
      $audit=Get-Content -LiteralPath (Join-Path $dir 'connection_audit.json') -Raw | ConvertFrom-Json
      if(!$audit.inverse_transform_recovers_original){throw 'Connection-equivalence audit missing'}
      foreach($pair in @(@((Join-Path $original 'timing.sdf'),$audit.unchanged_native_sdf_sha256),@((Join-Path $original 'timing.v'),$audit.original_netlist_sha256),@((Join-Path $dir 'timing.v'),$audit.normalized_netlist_sha256))){
        if((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash.ToLower() -ne $pair[1]){throw 'Audited simulation input changed'}
      }
    }
    $top=if($kind -eq 'mac'){'tb_mac_row_compare'}else{'tb_isolation'}
    $tb=if($kind -eq 'mac'){'tb_mac_row_compare.sv'}else{'tb_legacy_compare.sv'}
    if(!$ReuseSnapshot){
      & (Join-Path $VivadoBin 'xvlog.bat') -sv (Join-Path $dir 'timing.v') $tb (Join-Path $VivadoBin '../data/verilog/src/glbl.v') *> (Join-Path $dir 'compile.log')
      if($LASTEXITCODE){throw "$kind flattened timing compile failed"}
      & (Join-Path $VivadoBin 'xelab.bat') -L simprims_ver -L unisims_ver -L secureip $top glbl -s $snapshot --O0 --mt 2 --debug typical --timescale 1ns/1ps -transport_int_delays -pulse_r 0 -pulse_int_r 0 -pulse_e 0 -pulse_int_e 0 *> (Join-Path $dir 'elaborate.log')
      if($LASTEXITCODE -or (Select-String -LiteralPath (Join-Path $dir 'elaborate.log') -Pattern 'SDF backannotation was successful').Count -ne 1 -or (Select-String -LiteralPath (Join-Path $dir 'elaborate.log') -Quiet -Pattern 'ERROR:|WARNING:')){Get-Content (Join-Path $dir 'elaborate.log') -Tail 25;throw "$kind flattened timing annotation failed"}
    }
    $profiles=if($kind -eq 'mac'){@('ACTUAL','DENSE','MASKS','IDLE')}elseif($CarryPortAliases){@('CASE_5','ALL')}else{@('CASE_4','ALL')}
    foreach($profile in $profiles){
      $log=Join-Path $dir ($profile.ToLower()+'.log')
      if($profile -eq 'ALL'){
        & (Join-Path $VivadoBin 'xsim.bat') $snapshot -tclbatch run_all.tcl *> $log
      }else{
        & (Join-Path $VivadoBin 'xsim.bat') $snapshot --testplusarg $profile -tclbatch run_all.tcl *> $log
      }
      $expected=if($kind -eq 'mac'){'^PASS MAC_ROW_COMPARE'}elseif($profile -eq 'ALL'){'^PASS isolation: jobs=653 checked_rows_across_variants=13060'}else{'^PASS isolation: jobs=64 checked_rows_across_variants=1280'}
      if($LASTEXITCODE -or !(Select-String -LiteralPath $log -Quiet -Pattern $expected) -or (Select-String -LiteralPath $log -Quiet -Pattern 'Fatal:|Error:|[Tt]iming violation')){Get-Content $log -Tail 25;throw "$kind flattened replay failed: $profile"}
      Select-String -LiteralPath $log -Pattern '^PASS' | ForEach-Object {$_.Line}
    }
  }
} finally {Pop-Location}
