param([Parameter(Mandatory=$true)][string]$Work,[string]$VivadoBin='C:/Xilinx/Vivado/2023.2/bin',[switch]$FixedOnly)
$ErrorActionPreference='Stop'
Push-Location (Resolve-Path -LiteralPath $Work)
try {
  $source=Get-Content -LiteralPath tb_isolation.sv -Raw
  [System.IO.File]::WriteAllText((Join-Path (Get-Location) 'tb_isolation_netlist.sv'), ('`define PHY_NETLIST'+[Environment]::NewLine+$source))
  $netlists=@()
  $sdfBodies=@()
  $sdfCells=@{}
  foreach($variant in @('legacy','plain','retained','isolated','dual')){
    $netlist=Get-Content -LiteralPath "netlists/$variant.v" -Raw
    $annotation='(?s)initial\s+begin\s*\$sdf_annotate\([^;]+;\s*end'
    if([regex]::Matches($netlist,$annotation).Count -ne 1){throw "Missing automatic SDF annotation: $variant"}
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) "netlists/${variant}_explicit.v"),[regex]::Replace($netlist,$annotation,''))
    $netlists+="netlists/${variant}_explicit.v"
    $sdf=Get-Content -LiteralPath "netlists/$variant.sdf" -Raw
    $body=$sdf.Substring($sdf.IndexOf('(CELL')).TrimEnd()
    if(!$body.EndsWith(')')){throw "Invalid SDF wrapper: $variant"}
    $body=$body.Substring(0,$body.Length-1)
    $sdfCells[$variant]=[regex]::Matches($body,'\(INSTANCE\b').Count
    $body=[regex]::Replace($body,'\(INSTANCE\s*([^)]*)\)',{
      param($match)
      $instance=$match.Groups[1].Value.Trim()
      if($instance){return "(INSTANCE $variant/$instance)"}
      return "(INSTANCE $variant)"
    })
    $sdfBodies+=$body
  }
  $combined='(DELAYFILE (SDFVERSION "3.0") (DESIGN "tb_isolation") (VENDOR "XILINX") (DIVIDER /) (TIMESCALE 1ps)'+[Environment]::NewLine+($sdfBodies -join [Environment]::NewLine)+')'
  [System.IO.File]::WriteAllText((Join-Path (Get-Location) 'netlists/all.sdf'),$combined)
  $sdfCells | ConvertTo-Json | Set-Content -LiteralPath netlists/annotation_cells.json
  $glbl=Join-Path $VivadoBin '../data/verilog/src/glbl.v'
  & (Join-Path $VivadoBin 'xvlog.bat') -sv @netlists tb_isolation_netlist.sv $glbl *> phy_compile.log
  if($LASTEXITCODE){Get-Content phy_compile.log -Tail 30;throw 'Timing-netlist compile failed'}
  & (Join-Path $VivadoBin 'xelab.bat') -L simprims_ver -L unisims_ver -L secureip tb_isolation glbl -s isolation_timing --debug typical --timescale 1ns/1ps -transport_int_delays -pulse_r 0 -pulse_int_r 0 -pulse_e 0 -pulse_int_e 0 -sdfmax '"/tb_isolation=netlists/all.sdf"' *> phy_elaborate.log
  if($LASTEXITCODE){Get-Content phy_elaborate.log -Tail 35;throw 'Timing-netlist elaboration failed'}
  if((Select-String -LiteralPath phy_elaborate.log -Pattern 'SDF backannotation was successful').Count -ne 1 -or (Select-String -LiteralPath phy_elaborate.log -Quiet -Pattern 'WARNING:|ERROR:')){throw 'Combined SDF annotation must succeed without warnings'}
  & (Join-Path $VivadoBin 'xsim.bat') isolation_timing --testplusarg CASE_DIRECTED -tclbatch all.tcl *> phy_directed.log
  if($LASTEXITCODE -or !(Select-String -LiteralPath phy_directed.log -Quiet -Pattern '^PASS isolation: jobs=141 checked_rows_across_variants=2820 latency_min=8 latency_max=8 case=8') -or (Select-String -LiteralPath phy_directed.log -Quiet -Pattern 'Fatal:|Error:|Timing violation|timing violation')){Get-Content phy_directed.log -Tail 35;throw 'SDF directed regression failed'}
  Select-String -LiteralPath phy_directed.log -Pattern '^PASS isolation:' | ForEach-Object {$_.Line}
  $cases=0..7
  if($FixedOnly){$cases=0..3}
  foreach($case in $cases){
    $caseDir=Join-Path (Get-Location) "phy_case_$case"
    New-Item -ItemType Directory -Path $caseDir -Force | Out-Null
    $saif=(Join-Path $caseDir 'activity.saif').Replace('\','/')
    [System.IO.File]::WriteAllText((Join-Path $caseDir 'activity.tcl'), "open_saif {$saif}`nlog_saif [get_objects -r /tb_isolation/*]`nrun all`nclose_saif`nexit`n")
    & (Join-Path $VivadoBin 'xsim.bat') isolation_timing --testplusarg "CASE_$case" -tclbatch "phy_case_$case/activity.tcl" *> "phy_case_$case/run.log"
    if($LASTEXITCODE -or !(Select-String -LiteralPath "phy_case_$case/run.log" -Quiet -Pattern "^PASS isolation: jobs=64 checked_rows_across_variants=1280 latency_min=8 latency_max=8 case=$case") -or (Select-String -LiteralPath "phy_case_$case/run.log" -Quiet -Pattern 'Fatal:|Error:|Timing violation|timing violation')){Get-Content "phy_case_$case/run.log" -Tail 35;throw "SDF case failed: $case"}
    Select-String -LiteralPath "phy_case_$case/run.log" -Pattern '^PASS isolation:' | ForEach-Object {$_.Line}
  }
}finally{Pop-Location}
