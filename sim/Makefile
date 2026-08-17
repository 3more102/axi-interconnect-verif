# =============================================================================
# sim/Makefile -- Icarus Verilog flow for the AXI4 interconnect project
# Implements VERIF_PLAN.md section 5. Run from this directory (WSL / Linux).
#
#   make compile                              build all four testbenches
#   make run TB=<tb> TEST=<t> [SEED=n] [DUMP=1]   one run, logged
#   make regress                              full matrix, then ./report.sh
#   make synth                                Yosys elaboration sanity on rtl/
#   make clean
#
# Simulator output is always REDIRECTED to a log and the log is then read.
# It is never piped: a pipeline's exit status is the last stage's, so
# `vvp ... | tail` reports success even when the run failed.
# =============================================================================

IVERILOG ?= iverilog
VVP      ?= vvp
YOSYS    ?= yosys
IVFLAGS  ?= -g2012

RTL := $(wildcard ../rtl/*.v)
TBS := $(wildcard ../tb/*.v)
SRC := $(RTL) $(TBS)

BUILD := build
LOGS  := logs

TB   ?= tb_axi4_lite_slave
TEST ?= smoke
SEED ?=
DUMP ?=

# Regression matrix (VERIF_PLAN.md section 3). 23 distinct tests; the four
# `random` tests are additionally rerun at SEED=7, giving 27 runs.
REGRESS_S1 := \
  tb_axi4_lite_slave:smoke \
  tb_axi4_lite_slave:strobes \
  tb_axi4_lite_slave:errors \
  tb_axi4_lite_slave:aliasing \
  tb_axi4_lite_slave:random \
  tb_axi4_lite_interconnect:targeted \
  tb_axi4_lite_interconnect:decerr \
  tb_axi4_lite_interconnect:contention \
  tb_axi4_lite_interconnect:parallel \
  tb_axi4_lite_interconnect:random \
  tb_axi4_mem_slave:smoke \
  tb_axi4_mem_slave:incr \
  tb_axi4_mem_slave:wrap \
  tb_axi4_mem_slave:fixed \
  tb_axi4_mem_slave:narrow \
  tb_axi4_mem_slave:errors \
  tb_axi4_mem_slave:boundary \
  tb_axi4_mem_slave:random \
  tb_axi4_interconnect:targeted \
  tb_axi4_interconnect:decerr \
  tb_axi4_interconnect:parallel \
  tb_axi4_interconnect:contention \
  tb_axi4_interconnect:random

REGRESS_S7 := \
  tb_axi4_lite_slave:random \
  tb_axi4_lite_interconnect:random \
  tb_axi4_mem_slave:random \
  tb_axi4_interconnect:random

.PHONY: all compile run regress synth clean

all: compile

$(BUILD) $(LOGS):
	@mkdir -p $@

compile: $(BUILD)/tb_axi4_lite_slave.vvp \
         $(BUILD)/tb_axi4_lite_interconnect.vvp \
         $(BUILD)/tb_axi4_mem_slave.vvp \
         $(BUILD)/tb_axi4_interconnect.vvp

$(BUILD)/tb_axi4_lite_slave.vvp: filelists/lite_slave.f $(SRC) | $(BUILD)
	$(IVERILOG) $(IVFLAGS) -o $@ -f $<

$(BUILD)/tb_axi4_lite_interconnect.vvp: filelists/lite_ic.f $(SRC) | $(BUILD)
	$(IVERILOG) $(IVFLAGS) -o $@ -f $<

$(BUILD)/tb_axi4_mem_slave.vvp: filelists/mem_slave.f $(SRC) | $(BUILD)
	$(IVERILOG) $(IVFLAGS) -o $@ -f $<

$(BUILD)/tb_axi4_interconnect.vvp: filelists/ic.f $(SRC) | $(BUILD)
	$(IVERILOG) $(IVFLAGS) -o $@ -f $<

# ---- single run -------------------------------------------------------------
run: $(BUILD)/$(TB).vvp | $(LOGS)
	@args="+TEST=$(TEST)"; log="$(LOGS)/$(TB)__$(TEST)"; \
	if [ -n "$(SEED)" ]; then args="$$args +SEED=$(SEED)"; log="$${log}__s$(SEED)"; fi; \
	if [ -n "$(DUMP)" ]; then args="$$args +DUMP"; fi; \
	log="$${log}.log"; \
	$(VVP) $(BUILD)/$(TB).vvp $$args > "$$log" 2>&1; \
	if grep -q '=== TEST PASSED' "$$log"; then \
	  echo "PASS  $(TB)  $(TEST)  seed=$${SEED:-1}"; \
	else \
	  echo "FAIL  $(TB)  $(TEST)  seed=$${SEED:-1}   -> $$log"; exit 1; \
	fi

# ---- full regression --------------------------------------------------------
# Individual failures must not abort the sweep, so `make run` failures are
# tolerated here; report.sh is what decides the overall verdict and exit code.
regress: compile | $(LOGS)
	@rm -f $(LOGS)/*.log
	@for spec in $(REGRESS_S1); do \
	  tb=$${spec%%:*}; test=$${spec##*:}; \
	  $(MAKE) --no-print-directory run TB=$$tb TEST=$$test SEED=1 || true; \
	done
	@for spec in $(REGRESS_S7); do \
	  tb=$${spec%%:*}; test=$${spec##*:}; \
	  $(MAKE) --no-print-directory run TB=$$tb TEST=$$test SEED=7 || true; \
	done
	@./report.sh

# ---- synthesis sanity -------------------------------------------------------
synth:
	$(YOSYS) -p 'read_verilog $(RTL); hierarchy -check; proc; opt; stat'

clean:
	rm -rf $(BUILD) $(LOGS) *.vcd
