database -open waves -into waves.shm -default
scope -set hdl_top.u_dut
probe -create -all -depth all -waveform
run 5 us
puts "Waveform run paused at 5 us. Use csh run.csh uvm separately for the completed verification report."
