param([int[]]$Seeds=@(1,7,23),[string]$VivadoBin='C:/Xilinx/Vivado/2023.2/bin',[switch]$CodeCoverage,[ValidateSet('sbct','sbc')][string]$CoverageTypes='sbc',[switch]$KeepWork)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workspace=Split-Path $root -Parent
$work=Join-Path $workspace ('.cleanup/uvm-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$work=(Resolve-Path $work).Path
$sources=@(Get-Content (Join-Path $PSScriptRoot 'verification.f') | Where-Object {$_.Trim()} | ForEach-Object {Join-Path $root $_})
$sources+=@('uvm_tb/tb/ref.sv','asic/uvm/stream_if.sv','asic/uvm/uvm_pkg.sv','asic/uvm/stream_top.sv') | ForEach-Object {Join-Path $root $_}
Copy-Item (Join-Path $root 'evaluation/data/model.mem'),(Join-Path $root 'evaluation/data/inputs.mem') $work
Push-Location $work
$passed=$false
try {
  & (Join-Path $VivadoBin 'xvlog.bat') -sv -L uvm @sources *> compile.log
  if($LASTEXITCODE) {Get-Content compile.log -Tail 40; throw 'UVM compilation failed'}
  $coverageOptions=@()
                                                                               
  if($CodeCoverage){$coverageOptions=@('--cc_type',$CoverageTypes,'--cc_db','stream_uvm','--cc_dir','.')}
  & (Join-Path $VivadoBin 'xelab.bat') stream_top -L uvm -s stream_uvm --timescale 1ns/1ps @coverageOptions *> elaborate.log
  if($LASTEXITCODE) {Get-Content elaborate.log -Tail 40; throw 'UVM elaboration failed'}
  foreach($seed in $Seeds) {
    $log="uvm_seed_$seed.log"
    & (Join-Path $VivadoBin 'xsim.bat') stream_uvm -runall -sv_seed $seed *> $log
    if($LASTEXITCODE -or !(Select-String -LiteralPath $log -Quiet -Pattern 'PASS stream_model_test') -or (Select-String -LiteralPath $log -Quiet -Pattern '(UVM_ERROR|UVM_FATAL)\s+@|Fatal:|Error:')) {
      Get-Content $log -Tail 50; throw "UVM simulation failed: seed $seed"
    }
    Write-Output "Seed: $seed"
    Select-String -LiteralPath $log -Pattern 'COUNTS|PASS stream_model_test|UVM_ERROR :|UVM_FATAL :' | ForEach-Object {$_.Line}
    if($CodeCoverage){
      $saved=Join-Path $work "seed_$seed"
      New-Item -ItemType Directory -Force -Path $saved | Out-Null
      Copy-Item (Join-Path $work 'xsim.codeCov') $saved -Recurse -Force
    }
  }
  $artifacts=@('compile.log','elaborate.log')+@($Seeds | ForEach-Object {"uvm_seed_$_.log"})
  if($CodeCoverage){
    $merge=@('-merge_cc','-cc_merge_dir','merged','-cc_merge_db','stream_uvm_merged','-cc_report','merged/report','-report_format','html')
    foreach($seed in $Seeds){$merge+=@('-cc_dir',"seed_$seed",'-cc_db','stream_uvm')}
    & (Join-Path $VivadoBin 'xcrg.bat') @merge *> coverage_merged.log
    if($LASTEXITCODE){Get-Content coverage_merged.log -Tail 30; throw 'Coverage reporting failed; no closure claim is permitted'}
    $artifacts+=@('coverage_merged.log','merged')+@($Seeds | ForEach-Object {"seed_$_"})
  }
  $reports=Join-Path $PSScriptRoot 'reports'
  New-Item -ItemType Directory -Force -Path $reports | Out-Null
  $archive=Join-Path $reports $(if($CodeCoverage){'uvm_code_coverage.zip'}else{'uvm.zip'})
  Compress-Archive -LiteralPath $artifacts -DestinationPath $archive -Force
  $passed=$true
  Write-Output "Evidence: $archive"
} finally {
  Pop-Location
  if($passed -and !$KeepWork){
    $resolved=(Resolve-Path -LiteralPath $work).Path
    $allowed=(Join-Path $workspace '.cleanup')+[IO.Path]::DirectorySeparatorChar
    if(!$resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing cleanup outside generated workspace'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
  } else {Write-Output "Intermediate files retained for debugging: $work"}
}
