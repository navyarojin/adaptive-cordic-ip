database -open waves -into waves.shm -default
scope -set hdl_top.u_dut
probe -create hdl_top -shm -all -depth all
run 5 us
puts "Waveform run paused at 5 us. Use csh run.csh uvm separately for the completed verification report."
