.PHONY: all pre_sim input_gen sim output_anal clean

SCENARIO ?= IMG_STREAM
STALL_MAX ?= 0
MONITOR ?= 0
TIMEOUT_NS ?= 200000
INJECT_ERROR ?= 0
INJECT_ADDR_ERROR ?= 0

all: clean pres_sim input_gen sim output_anal

pre_sim:
	touch env/src_mem.txt
	touch env/dst_mem_0.txt
	touch env/dst_mem_1.txt
	touch env/dst_mem_0_format.txt
	touch env/dst_mem_1_format.txt

input_gen:
	python3 env/img2txt.py

sim:
	$(MAKE) -f tool_run \
	SCENARIO=$(SCENARIO) \
	STALL_MAX=$(STALL_MAX) \
	MONITOR=$(MONITOR) \
	TIMEOUT_NS=$(TIMEOUT_NS) \
	INJECT_ERROR=$(INJECT_ERROR) \
	INJECT_ADDR_ERROR=$(INJECT_ADDR_ERROR)

output_anal:
	python3 env/txt2img.py
	mv env/output_channel_* . 2>/dev/null || true

clean:
	rm -f env/src_mem.txt
	rm -f env/dst_mem_0.txt
	rm -f env/dst_mem_1.txt
	rm -f env/dst_mem_0_format.txt
	rm -f env/dst_mem_1_format.txt
	rm -f env/dst_mem_0.png
	rm -f env/dst_mem_1.png
	rm -f output_channel_*