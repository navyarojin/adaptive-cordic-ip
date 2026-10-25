param(
  [string]$VivadoBin='C:/Xilinx/Vivado/2023.2/bin',
  [string[]]$Tests=@('tb_mac4_stream','tb_fused_layer','tb_stream_job_engine','tb_activation_stream_array','tb_stream_throughput','tb_systolic_param','tb_cordic_stream','tb_divider_stream','tb_stream_learning','tb_command_queue','tb_accelerator','tb_spi_bridge','tb_npu_spi')
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$work=Join-Path ([System.IO.Path]::GetTempPath()) ('npu-compute-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$sources=@(Get-Content -LiteralPath (Join-Path $root 'rtl/sources.f') | Where-Object { $_.Trim() } | ForEach-Object {Join-Path $root $_})
$sources+=@('uvm_tb/tb/ref.sv','verification/tb_mac.sv','fpga/sim/tb_fused.sv','verification/tb_jobs.sv','verification/tb_array.sv','verification/tb_rate.sv','verification/tb_systolic.sv','verification/tb_cordic_stream.sv','verification/tb_div_stream.sv','verification/tb_learn.sv','verification/tb_queue.sv','verification/tb_accel.sv','spi_tb/spi_if.sv','spi_tb/tb_spi.sv') | ForEach-Object {Join-Path $root $_}
Write-Output "Logs: $work"
Push-Location $work
try {
  & (Join-Path $VivadoBin 'xvlog.bat') -sv @sources *> compile.log
  if($LASTEXITCODE) {Get-Content compile.log -Tail 30; throw 'Compile failed'}
  foreach($test in $Tests) {
    & (Join-Path $VivadoBin 'xelab.bat') $test -s $test --debug typical --timescale 1ns/1ps *> "$test.elaborate.log"
    if($LASTEXITCODE) {Get-Content "$test.elaborate.log" -Tail 30; throw "Elaboration failed: $test"}
    & (Join-Path $VivadoBin 'xsim.bat') $test -runall *> "$test.run.log"
    if($LASTEXITCODE -or !(Select-String -LiteralPath "$test.run.log" -Quiet -Pattern '^PASS|^STREAM_THROUGHPUT') -or (Select-String -LiteralPath "$test.run.log" -Quiet -Pattern 'Fatal:|FATAL|Error:')) {
      Get-Content "$test.run.log" -Tail 30; throw "Simulation failed: $test"
    }
    if($test -eq 'tb_stream_throughput' -and @(Select-String -LiteralPath "$test.run.log" -Pattern '^STREAM_THROUGHPUT').Count -ne 3) {throw 'Incomplete throughput test'}
    Select-String -LiteralPath "$test.run.log" -Pattern '^PASS|^STREAM_THROUGHPUT' | ForEach-Object {$_.Line}
  }
} finally {Pop-Location}
