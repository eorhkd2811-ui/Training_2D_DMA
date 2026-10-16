log_wave -r /

file mkdir ./dump

open_vcd ./dump/sim_dump.vcd
log_vcd [get_objects -r /*]

run all

close_vcd

quit