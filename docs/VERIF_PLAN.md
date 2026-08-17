# Verification Plan — AXI4-Lite / AXI4 Interconnect Project

Companion to [SPEC.md](SPEC.md). Defines what is verified, by which test,
how it is checked, and what the regression/coverage closure criteria are.

## 1. Feature → test matrix

| # | Feature | Checked by | Test(s) |
|---|---------|-----------|---------|
| F01 | Lite write (AW/W any order, B resp) | scoreboard + lite checker | lite_slave: smoke, random |
| F02 | Lite byte strobes | scoreboard | lite_slave: strobes, random |
| F03 | Lite SLVERR on invalid index, state preserved | scoreboard | lite_slave: errors |
| F04 | Lite address aliasing ([31:6],[1:0] ignored) | scoreboard | lite_slave: aliasing |
| F05 | Lite handshake legality (stability, no X, reset) | PC01–07, PC12 | all lite tests |
| F06 | Lite interconnect decode (2 targets + DECERR) | scoreboard | lite_ic: targeted, decerr |
| F07 | Lite interconnect arbitration + grant locking | scoreboard, completion | lite_ic: contention |
| F08 | Lite interconnect concurrency (crossbar paths) | scoreboard | lite_ic: parallel, random |
| F09 | AXI4 single-beat & INCR bursts (len 0–255) | scoreboard | mem: smoke, incr, random |
| F10 | AXI4 WRAP bursts (len 1/3/7/15, wrap math) | scoreboard | mem: wrap |
| F11 | AXI4 FIXED bursts | scoreboard | mem: fixed |
| F12 | AXI4 narrow transfers (size 0/1, lanes/strobes) | scoreboard | mem: narrow |
| F13 | AXI4 per-beat SLVERR + partial-burst semantics | scoreboard + rresp_buf | mem: errors, boundary |
| F14 | WLAST/RLAST correctness | PC08, PC09, BFM | all AXI4 tests |
| F15 | WRAP legality, 4KB rule at issue | PC10, PC11 | mem: wrap, random |
| F16 | ID reflection (BID/RID == request ID) | BFM bid/rid checks | mem: random (multi-ID) |
| F17 | AXI4 interconnect decode + default DECERR slave (burst-capable) | scoreboard | ic: targeted, decerr |
| F18 | AXI4 interconnect ID extension/routing ({midx,id}) | BFM id checks + scoreboard | ic: all |
| F19 | AXI4 write-path lock AW→WLAST (no W interleave) | PC08 on master ports + scoreboard | ic: contention, random |
| F20 | AXI4 R-mux per-burst lock (no R interleave at master port) | PC09 on slave ports + BFM | ic: parallel, random |
| F21 | Round-robin fairness (no starvation) | both masters complete | lite_ic/ic: contention |
| F22 | Crossbar concurrency (distinct paths in parallel) | scoreboard | ic: parallel |
| F23 | Reset behavior (valids low in reset) | PC12 | all tests |

## 2. Checking strategy (three independent nets)

1. **Scoreboards** — reference models in each TB, write-before-read data
   checking, expected-response checking (per-address/per-beat).
2. **Protocol checkers** — passive monitors on every interface, structural
   AXI legality (PC01–PC13), zero-tolerance.
3. **BFM self-checks** — ID reflection, RLAST position, response capture.

A test passes only if **all three** report zero errors AND the test's own
sequencing completed (watchdog not hit).

## 3. Regression matrix (20 runs)

| TB | Tests |
|----|-------|
| tb_axi4_lite_slave | smoke, strobes, errors, aliasing, random |
| tb_axi4_lite_interconnect | targeted, decerr, contention, parallel, random |
| tb_axi4_mem_slave | smoke, incr, wrap, fixed, narrow, errors, boundary, random |
| tb_axi4_interconnect | targeted, decerr, parallel, contention, random |

(23 runs total. Default seed 1; regression must also be clean with SEED=7 for
the `random` tests — the regression script runs random tests twice.)

## 4. Coverage closure

`axi4_coverage` instances on tb_axi4_mem_slave (1) and tb_axi4_interconnect
slave ports (2). Goal: **100% of §9 bins** hit across the regression union;
the len=16–255 INCR bin and boundary bin may be hit by mem-slave tests only.
Coverage report is printed per-test; the regression script aggregates by
grepping `COVERAGE` lines.

## 5. Sim infrastructure contract (`sim/`)

### `sim/filelists/*.f` (Icarus -f files, paths relative to `sim/`)
- `lite_slave.f`, `lite_ic.f`, `mem_slave.f`, `ic.f` — each lists the needed
  `../rtl/*.v` and `../tb/*.v` files, one per line, TB top last.

### `sim/Makefile` (GNU make, run from WSL in `sim/`)
- `make compile` — builds all four TBs with
  `iverilog -g2012 -o build/<tb>.vvp -f filelists/<x>.f` (RTL is Verilog-2001-clean
  but compiled together with TB under -g2012, which is fine).
- `make run TB=<tb_name> TEST=<test> [SEED=n] [DUMP=1]` — single run via
  `vvp build/<tb>.vvp +TEST=<test> [+SEED=n] [+DUMP]`, log to
  `logs/<tb>__<test>[__s<n>].log`.
- `make regress` — full §3 matrix (random tests at SEED=1 and SEED=7), then
  invokes `./report.sh`.
- `report.sh` — greps logs for `TEST PASSED`/`TEST FAILED`, prints a result
  table and `REGRESSION: N/M PASSED`, exit code 1 on any failure; also prints
  aggregated `COVERAGE` lines.
- `make synth` — `yosys -p 'read_verilog ../rtl/*.v; hierarchy; proc; opt; stat'`
  sanity (no synthesis errors allowed).
- `make clean`.

### `sim/modelsim/run_all.do` + `sim/modelsim/run_modelsim.ps1`
- `.do`: `vlib work; vlog` all RTL (plain) and `vlog -sv` all TB files, then for
  each regression entry: `vsim -c +TEST=<t> work.<tb>; run -all` (use
  `onfinish stop` so `$finish` doesn't kill vsim between runs; `onerror`
  continue pattern as in the LeNet5 project's `scripts/modelsim.do` — read that
  file as reference for ASE-compatible batch chaining). End with `quit -f`.
- `.ps1`: from repo root, `Push-Location sim/modelsim; vsim -c -do run_all.do`
  then scan the transcript for `TEST FAILED` / missing `TEST PASSED` count and
  print a summary table; nonzero exit on failure.

## 6. Known-answer error tests

Negative testing is deliberate and expected-response-driven (never "test
passes because nothing was checked"): every error test asserts the *exact*
response code and, where applicable, that state was not corrupted.

## 7. Bug-injection (mutation) audit — run after regression is green

At least 8 single-line mutations applied one at a time to a scratch copy of
the RTL (e.g. break WLAST termination, swap RR priority, wrong WRAP boundary
mask, DECERR→OKAY, drop a WSTRB lane, BID routing bit flipped, arbiter lock
released early, SLVERR threshold off-by-one). For each: run the regression
subset covering that feature; **at least one test must fail**. Record the kill
matrix in `docs/MUTATION_RESULTS.md`. A surviving mutant means a verification
hole: add/strengthen a test and re-run.
