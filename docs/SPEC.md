# AXI4-Lite / AXI4 Interconnect Verification Project — Design Specification

This document is the **authoritative contract** for every RTL module, BFM, checker,
and testbench in this project. All files must match the interfaces and behaviors
defined here exactly — module names, port names, parameter names, task signatures.

## 0. Global rules (apply to every file)

- **Language subset (dual-simulator portability is non-negotiable):**
  - RTL (`rtl/*.v`): pure **Verilog-2001**. `reg`/`wire` only. No SystemVerilog
    keywords (no `logic`, `always_ff`, `always_comb`, typedef, interface, package).
    Must compile with `iverilog -g2001` standalone and be Yosys-synthesizable.
  - TB (`tb/*.v`): Verilog-2001 **plus** these SV features only: `$urandom`,
    `$urandom_range`, string plusargs via `$value$plusargs`. Compiled with
    `iverilog -g2012` and `vlog -sv` (ModelSim ASE 10.5b). **Forbidden:** classes,
    covergroups, SVA (`assert property`), `program`, `interface`, `clocking`,
    `randomize()`, mailboxes, semaphores, queues (`$` bounds), dynamic arrays,
    associative arrays, `foreach`, `string` type (use `reg [8*32-1:0]` for test
    names), automatic tasks containing event controls. Plain `fork/join` IS allowed.
  - Tasks in BFMs are **static** (not automatic). Each BFM instance is driven by
    exactly one sequential test thread, so static locals are safe.
- **Clock/reset:** single clock `aclk` (10 ns period, generated in TB), single
  active-low synchronous-deassert reset `aresetn`. All RTL state resets when
  `aresetn == 0` (synchronous reset, `always @(posedge aclk)` with
  `if (!aresetn)`). All `*valid` outputs must be 0 during reset.
- **AXI signal subset:** we implement ID/ADDR/LEN/SIZE/BURST/PROT + data/resp
  channel signals. **Omitted entirely** (not in any port list): LOCK, CACHE,
  QOS, REGION, USER. AXI4-Lite omits ID/LEN/SIZE/BURST/LAST as per the Lite spec.
- **Widths:** ADDR = 32, DATA = 32, STRB = 4 everywhere. AXI4 ID width is a
  parameter `ID_WIDTH` (default 4).
- Every violation/message printed by checkers/TBs uses format
  `[<BLOCK>] %0t ...` via `$display`.
- No `initial` blocks in RTL (except none at all). No delays (`#`) in RTL.

## 1. Address map (both interconnects)

| Range | Target |
|---|---|
| `0x0000_0000 – 0x0000_0FFF` | Slave port M0 (S0 device) |
| `0x0000_1000 – 0x0000_1FFF` | Slave port M1 (S1 device) |
| anything else | internal default slave → **DECERR** |

Decode is `addr[31:12]`: `20'h00000` → M0, `20'h00001` → M1, else default.
Default-slave read data is `32'hDEC0DE00`.

## 2. `rtl/axi4_lite_slave.v` — module `axi4_lite_slave`

```verilog
module axi4_lite_slave #(
    parameter NUM_REGS = 12          // valid word indices 0..NUM_REGS-1 (max 16)
)(
    input  wire        aclk,
    input  wire        aresetn,
    // write address
    input  wire [31:0] s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    // write data
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    // write response
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    // read address
    input  wire [31:0] s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    // read data
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready
);
```

Behavior:
- 16 × 32-bit register file, register index = `addr[5:2]`; address bits [31:6]
  and [1:0] are **ignored** (the 64-byte window aliases across the 4 KB region —
  documented feature, exercised by tests).
- Index `>= NUM_REGS` → response `SLVERR (2'b10)`; writes to invalid index do
  not modify state; reads of invalid index return `32'h0000_0000`.
- Write: AW and W are accepted **independently** (either order, any gap). Once
  both have been captured, `bvalid` rises the following cycle and holds until
  `bready`. Only one outstanding write (awready/wready stay low from capture
  until B handshake completes).
- Byte strobes honored on valid writes (`wstrb[i]` gates byte lane i).
- Read: `arready` high when idle; captured AR produces `rvalid` the next cycle,
  data/resp held until `rready`. One outstanding read.
- Reads and writes are independent (concurrent write & read allowed).
- OKAY = `2'b00`, SLVERR = `2'b10`.

## 3. `rtl/axi4_lite_interconnect.v` — module `axi4_lite_interconnect`

2 master ports in, 2 slave ports out + internal DECERR default slave.
**Naming convention (Xilinx style): `s0_axi_*`, `s1_axi_*` are where the two
masters connect (interconnect acts as slave); `m0_axi_*`, `m1_axi_*` are where
the two slaves connect (interconnect acts as master).**

```verilog
module axi4_lite_interconnect (
    input  wire aclk,
    input  wire aresetn,
    // s0_axi_* : full AXI4-Lite slave port (same signal set as axi4_lite_slave's s_axi_*)
    // s1_axi_* : ditto
    // m0_axi_* : full AXI4-Lite master port (mirrored directions)
    // m1_axi_* : ditto
);
```
(Write out all ports explicitly; directions mirror appropriately.)

Behavior:
- Decode per §1 on `awaddr`/`araddr` of each master port.
- **Write path:** per-destination round-robin arbitration between the two
  masters. A write grant is claimed at AW handshake acceptance and held until
  the **B handshake** completes (single outstanding write per destination).
  The granted master's AW, W are routed to the destination; B routed back.
  While one master holds a destination, the other's AW to the same destination
  stalls (awready low); its AW to a *different* destination proceeds
  independently (true crossbar: M0→S0 and M1→S1 concurrently is required to work).
- **Read path:** identical structure, independent from write path; grant held
  from AR acceptance until R handshake completes.
- **Round-robin:** after a master completes a transaction on a destination, the
  *other* master has priority next time both request that destination
  simultaneously.
- **Default slave** (internal): any decode miss gets `DECERR (2'b11)`; write:
  accept AW+W then respond B=DECERR; read: respond `rdata = 32'hDEC0DE00`,
  `rresp = DECERR`. Same single-outstanding + arbitration structure as a real
  destination.
- Each master port supports **one outstanding write and one outstanding read**
  at a time (its awready/arready go low while its transaction is in flight).

## 4. `rtl/axi4_mem_slave.v` — module `axi4_mem_slave` (full AXI4)

```verilog
module axi4_mem_slave #(
    parameter ID_WIDTH  = 4,
    parameter MEM_BYTES = 3072       // bytes 0..MEM_BYTES-1 valid within 4KB window
)(
    input  wire                aclk,
    input  wire                aresetn,
    // write address
    input  wire [ID_WIDTH-1:0] s_axi_awid,
    input  wire [31:0]         s_axi_awaddr,
    input  wire [7:0]          s_axi_awlen,
    input  wire [2:0]          s_axi_awsize,
    input  wire [1:0]          s_axi_awburst,
    input  wire [2:0]          s_axi_awprot,
    input  wire                s_axi_awvalid,
    output wire                s_axi_awready,
    // write data
    input  wire [31:0]         s_axi_wdata,
    input  wire [3:0]          s_axi_wstrb,
    input  wire                s_axi_wlast,
    input  wire                s_axi_wvalid,
    output wire                s_axi_wready,
    // write response
    output wire [ID_WIDTH-1:0] s_axi_bid,
    output wire [1:0]          s_axi_bresp,
    output wire                s_axi_bvalid,
    input  wire                s_axi_bready,
    // read address
    input  wire [ID_WIDTH-1:0] s_axi_arid,
    input  wire [31:0]         s_axi_araddr,
    input  wire [7:0]          s_axi_arlen,
    input  wire [2:0]          s_axi_arsize,
    input  wire [1:0]          s_axi_arburst,
    input  wire [2:0]          s_axi_arprot,
    input  wire                s_axi_arvalid,
    output wire                s_axi_arready,
    // read data
    output wire [ID_WIDTH-1:0] s_axi_rid,
    output wire [31:0]         s_axi_rdata,
    output wire [1:0]          s_axi_rresp,
    output wire                s_axi_rlast,
    output wire                s_axi_rvalid,
    input  wire                s_axi_rready
);
```

Behavior:
- Backing store: `reg [31:0] mem [0:1023]` (full 4 KB window). Word index =
  `addr[11:2]`; address bits [31:12] ignored (window aliasing).
- **Valid range:** byte offset (`addr[11:0]`) `< MEM_BYTES` → OKAY; otherwise
  SLVERR *for that beat*.
- **Burst types:** FIXED (`2'b00`, address constant), INCR (`2'b01`,
  address += 2^size each beat), WRAP (`2'b10`, wrap boundary = (start address
  aligned down to (len+1)·2^size) + (len+1)·2^size). Compute the per-beat
  address sequence exactly per AXI4 spec. `2'b11` treated as INCR.
- **Narrow transfers** (size 0/1/2 on the 32-bit bus): the slave always
  reads/writes the addressed **word** (`addr[11:2]`); write lanes are selected
  purely by `wstrb` (master/BFM drives correct lanes); read always returns the
  full word on `rdata` (correct for a 32-bit data bus — master samples its lanes).
- **Write flow:** `awready` high when write engine idle. After AW capture,
  `wready` high; each W beat applies strobes at the current beat address (beats
  whose offset is out of range are **discarded**, in-range beats are written);
  beat address advances per burst type using AW*SIZE stepping. After the beat
  where `wlast` is observed, `bvalid` rises the next cycle; `bresp` = SLVERR if
  **any** beat was out of range, else OKAY; `bid` = captured `awid`. WLAST
  mistiming is the checker's concern, not the slave's: the slave ends the burst
  on `wlast` regardless.
- **Read flow:** `arready` high when read engine idle. After AR capture, R
  beats stream with `rvalid` held high continuously (data held while `rready`
  low); per-beat `rresp` (OKAY/SLVERR per beat offset), out-of-range beats
  return `32'h0000_0000`; `rlast` on beat `arlen+1`; `rid` = captured `arid`.
- One outstanding write and one outstanding read (independent engines).

## 5. `rtl/axi4_interconnect.v` — module `axi4_interconnect` (full AXI4)

```verilog
module axi4_interconnect #(
    parameter ID_WIDTH = 4            // master-side ID width; slave-side is ID_WIDTH+1
)(
    input wire aclk,
    input wire aresetn,
    // s0_axi_*, s1_axi_* : full AXI4 slave ports, ID width = ID_WIDTH
    // m0_axi_*, m1_axi_* : full AXI4 master ports, ID width = ID_WIDTH+1
);
```
Signal set identical to §4's list (with LEN/SIZE/BURST/LAST/ID everywhere).

Behavior:
- Decode per §1 on AW/AR addresses. 2 masters × (2 slaves + internal default
  DECERR slave), independent read and write paths, true crossbar (M0→S0
  concurrent with M1→S1 must work in both directions).
- **ID routing:** slave-side `awid/arid = {master_index, master_id}`
  (`master_index`: 1 bit, 0 for s0, 1 for s1). Responses route by
  `bid[ID_WIDTH]` / `rid[ID_WIDTH]`; the master sees its original ID
  (low bits).
- **Write path locking (AXI4 has no WID):** per destination, round-robin
  arbitrate AW between masters. Grant claimed at AW handshake and held through
  the **WLAST handshake** (AW and W of the winning master are routed together;
  the loser's AW to that destination stalls). After WLAST the AW/W path is
  released for re-arbitration; B returns independently, routed by BID MSB.
- **Read path locking:** per destination, round-robin arbitrate AR; grant
  released once the AR handshake completes (address-phase lock only). The **R
  return path to each master locks per burst**: once a slave starts returning
  R beats to a master port, that master port's R mux stays locked to that
  slave until RLAST (no beat interleaving at the master port).
- **Round-robin** fairness identical to §3.
- **Default slave** (internal, burst-capable): writes — accept AW, consume W
  beats until WLAST, single B=DECERR with reflected ID; reads — return
  `arlen+1` beats, `rdata=32'hDEC0DE00`, `rresp=DECERR` each beat, correct
  RLAST, reflected ID.
- Each master port: one outstanding write, one outstanding read.

## 6. `tb/axi4_lite_master_bfm.v` — module `axi4_lite_master_bfm`

Ports: `aclk`, `aresetn` inputs plus a full AXI4-Lite **master** interface named
`m_axi_awaddr, m_axi_awprot, m_axi_awvalid, m_axi_awready, m_axi_wdata,
m_axi_wstrb, m_axi_wvalid, m_axi_wready, m_axi_bresp, m_axi_bvalid,
m_axi_bready, m_axi_araddr, m_axi_arprot, m_axi_arvalid, m_axi_arready,
m_axi_rdata, m_axi_rresp, m_axi_rvalid, m_axi_rready` (directions from the
master's perspective; valid/addr/data outputs are `reg`).

- `integer max_delay;` initialized to 3 (TB may override hierarchically).
  Every delay below is `repeat ($urandom_range(0, max_delay)) @(posedge aclk);`
- All outputs driven to idle (valids 0) at reset / task end. Drive changes on
  `@(posedge aclk)` edges (nonblocking or blocking after edge — consistent).

```verilog
task axi_write (input [31:0] addr, input [31:0] data, input [3:0] strb,
                output [1:0] resp);
task axi_read  (input [31:0] addr, output [31:0] data, output [1:0] resp);
```

- `axi_write`: `fork` three threads: (a) random delay then drive AW until
  `awready`; (b) random delay then drive W until `wready`; (c) random delay
  then assert `bready`, wait `bvalid && bready`, capture `bresp`, drop
  `bready`; `join`. AWPROT/ARPROT driven 3'b000.
- `axi_read`: drive AR (random delay), then random delay, assert `rready`,
  capture `rdata/rresp` at `rvalid && rready`.

## 7. `tb/axi4_master_bfm.v` — module `axi4_master_bfm` (full AXI4)

Parameter `ID_WIDTH = 4`. Ports: `aclk`, `aresetn` + full AXI4 master interface
`m_axi_*` matching §4's signal set (mirrored directions).

Public data buffers (TB reads/writes these hierarchically):

```verilog
reg [31:0] wbuf [0:255];      // write payload, LSB-justified logical data per beat
reg [31:0] rbuf [0:255];      // read results, LSB-justified per beat
reg [1:0]  rresp_buf [0:255]; // per-beat read responses
integer    max_delay;         // default 3
```

```verilog
task axi_write_burst (input [ID_WIDTH-1:0] id, input [31:0] addr,
                      input [7:0] len, input [2:0] size, input [1:0] burst,
                      output [1:0] resp);
task axi_read_burst  (input [ID_WIDTH-1:0] id, input [31:0] addr,
                      input [7:0] len, input [2:0] size, input [1:0] burst,
                      output [1:0] resp);   // resp = worst rresp over the burst
```

- Lane handling: for beat i at beat-address A (computed per burst type/size,
  same rules as §4): byte lane offset `L = A % 4` (for size=2, L=0).
  `wdata = wbuf[i] << (8*L)`, `wstrb = ((1<<(1<<size))-1) << L`.
  On reads: `rbuf[i] = (rdata >> (8*L)) & mask`.
- `axi_write_burst`: AW then W beats with `$urandom_range(0,max_delay)` gaps,
  `wlast` on final beat only; then wait for B (with random bready delay),
  capture resp; **check `bid == id`** — on mismatch `$display("[BFM] ...")`
  and increment a public `integer bfm_errors;` (init 0).
- `axi_read_burst`: AR, then accept beats with random `rready` backpressure;
  fill `rbuf/rresp_buf`; `resp` = worst response seen (DECERR > SLVERR > OKAY);
  check `rid == id` each beat and `rlast` only on the final beat (increment
  `bfm_errors` on violation).
- Responses: OKAY=00, SLVERR=10, DECERR=11 (worst = numerically: treat 11 >
  10 > 00).

## 8. Protocol checkers

### `tb/axi4_lite_protocol_checker.v` — module `axi4_lite_protocol_checker`

Passive monitor. Inputs: `aclk`, `aresetn`, and every AXI4-Lite signal of one
interface (all inputs, named `awaddr, awprot, awvalid, awready, ...` without
prefix). Parameter `NAME = "PC"` (string, used in messages). Public
`integer error_count;` (init 0).

Checks (each numbered in messages):
- **PC01/02/03/04/05** (AW/W/AR/B/R): once VALID is high, VALID must stay high
  and payload must be stable until READY handshake.
- **PC06**: no X/Z on any VALID after reset deasserts.
- **PC07**: no X/Z on payload signals while corresponding VALID is high.
- **PC12**: all VALIDs low while `aresetn == 0` (sampled on posedge).

### `tb/axi4_protocol_checker.v` — module `axi4_protocol_checker`

Parameters `ID_WIDTH = 4`, `NAME = "PC"`. Inputs: full AXI4 signal set of one
interface (§4 list, unprefixed). Public `integer error_count;`.

Checks PC01–PC07, PC12 as above, plus:
- **PC08**: WLAST asserted on exactly the (AWLEN+1)-th W beat. (FIFO of
  accepted AWLENs, depth 4.)
- **PC09**: per-ID RLAST correctness: on AR handshake push `arlen` to that
  ID's queue (per-ID queue, depth 4, IDs up to 32); count R beats per RID;
  RLAST must coincide with count == len+1; also flags R beats for IDs with no
  outstanding AR.
- **PC10**: WRAP bursts must have len ∈ {1,3,7,15} and address aligned to 2^size.
- **PC11**: no burst may cross a 4 KB boundary (check at AW/AR handshake).
- **PC13**: B response for an ID with no outstanding write (per-ID outstanding
  write counters).

## 9. `tb/axi4_coverage.v` — module `axi4_coverage`

Passive functional-coverage collector for one full-AXI4 interface (same inputs
as §8 checker; parameter `NAME`). Counts, sampled at handshakes:

- write/read × burst type (FIXED/INCR/WRAP): 6 bins
- write/read × size (1B/2B/4B): 6 bins
- len bins: {0, 1–3, 4–15, 16–255} for INCR (write+read = 8 bins);
  WRAP len {1,3,7,15} (write+read = 8 bins)
- resp bins: B×{OKAY,SLVERR,DECERR}, R×{OKAY,SLVERR,DECERR} (6 bins)
- burst ending exactly at offset 0xFFF (boundary-adjacent): 1 bin

`task print_coverage;` prints a table: bin name, hit count, and a final
"COVERAGE <NAME>: X/Y bins hit (Z%)" line. A bin is hit if count > 0.

## 10. Testbenches (`tb/tb_*.v`)

Common skeleton for all four:
- 10 ns clock; `aresetn` low for 5 cycles then high.
- Test selection: `reg [255:0] testname; if (!$value$plusargs("TEST=%s", testname)) testname = "smoke";`
- Optional `+SEED=%d` (default 1): `integer seed; ... dummy = $urandom(seed);`
- Optional waves: `if ($test$plusargs("DUMP")) begin $dumpfile(...); $dumpvars(0, tb_xxx); end`
- Watchdog: `initial begin #5_000_000; $display("[TB] TIMEOUT"); print_summary_fail; $finish; end`
- `integer sb_errors;` scoreboard mismatch counter.
- Final verdict (a `task summary;`):
  `PASS = (sb_errors == 0) && (all checker error_counts == 0) && (all bfm_errors == 0)`
  Print exactly `=== TEST PASSED: <testname> ===` or
  `=== TEST FAILED: <testname> (sb=%0d pc=%0d bfm=%0d) ===`, then print
  coverage (where applicable), then `$finish;`
- Reference models: plain word arrays mirroring each slave
  (`reg [31:0] model0 [0:1023];` initialized to 0 like the DUT's... **note:**
  DUT memories are NOT initialized; therefore tests must **write before read**
  for every location they read — the models track writes and tests only read
  written locations, except error-path reads where data is don't-care).

### `tb_axi4_lite_slave.v`
DUT `axi4_lite_slave` (NUM_REGS=12) + one `axi4_lite_master_bfm` + lite checker
on the interface. Tests (`+TEST=`):
- `smoke`: write then readback a few registers, full strobes.
- `strobes`: per-byte strobe patterns on one register, verify merge behavior
  against model.
- `errors`: writes/reads to indices 12–15 → expect SLVERR, verify state
  untouched (readback of valid regs unchanged, invalid reads return 0).
- `aliasing`: write via `0x0000_0008`, read back via `0x0000_0048` and
  `0x0000_0F08` (same register).
- `random`: 200 random ops (mix write/read, random index 0–15, random strobes,
  random data), model-checked, expected resp per index.

### `tb_axi4_lite_interconnect.v`
DUT `axi4_lite_interconnect` + 2 lite slaves (NUM_REGS=12) at M0/M1 + 2 lite
BFMs + lite checkers on all 4 interconnect ports (distinct NAMEs). Tests:
- `targeted`: each master writes/reads each slave, model-checked.
- `decerr`: both masters access `0x0000_2000`/`0x8000_0000` → DECERR, reads
  return `32'hDEC0DE00`.
- `contention`: `fork` both masters hammering the **same** slave with
  interleaved writes/reads to *different* registers (each master owns a
  disjoint register set — no data races in the model), 50 ops each.
- `parallel`: fork M0→S0 while M1→S1 (50 ops each), then swap.
- `random`: fork both masters, 100 random ops each across the full map
  (each master owns a disjoint register subset of each slave + error/DECERR
  addresses), model-checked.

### `tb_axi4_mem_slave.v`
DUT `axi4_mem_slave` (ID_WIDTH=4, MEM_BYTES=3072) + one `axi4_master_bfm`
(ID_WIDTH=4) + AXI4 checker + `axi4_coverage`. Tests:
- `smoke`: single-beat (len=0, size=2) writes/readbacks.
- `incr`: INCR bursts len ∈ {0,1,3,7,15,31,255}, size=2, write→readback→compare.
- `wrap`: WRAP len ∈ {1,3,7,15}, size=2, aligned starts; verify wrap-around
  data placement via model.
- `fixed`: FIXED len ∈ {0,3}, size=2: write burst to one address (final beat
  value persists per strobes), readback burst returns same word repeatedly.
- `narrow`: size ∈ {0,1} INCR bursts at unaligned starts; verify lane handling
  via model.
- `errors`: bursts fully in `0xC00–0xFFF` → all-SLVERR; burst straddling
  `0xBFC→0xC04` → BRESP=SLVERR but in-range beats written (verify via
  readback), read straddle → per-beat mix of OKAY/SLVERR in `rresp_buf`.
- `boundary`: INCR burst ending exactly at offset `0xFFC` (last valid word)…
  which is in SLVERR region (offset ≥ 3072) — expect SLVERR per-beat, and an
  INCR burst ending exactly at `0xBFC` (last OKAY word) — expect OKAY.
- `random`: 100 random bursts (type/len/size/addr constrained to legal:
  no 4 KB crossing i.e. no offset+bytes overflow past 0xFFF, WRAP legal lens &
  aligned, random IDs), model-checked including expected per-beat resp.

### `tb_axi4_interconnect.v`
DUT `axi4_interconnect` (ID_WIDTH=4) + 2 × `axi4_mem_slave` (ID_WIDTH=5,
MEM_BYTES=3072) on M0/M1 + 2 × `axi4_master_bfm` (ID_WIDTH=4) + AXI4 checkers
on all 4 ports (slave-port checkers ID_WIDTH=4, master-port checkers
ID_WIDTH=5) + 2 × `axi4_coverage` on the slave ports. Tests:
- `targeted`: each master bursts to each slave (INCR len 7), model-checked.
- `decerr`: bursts to unmapped addresses from both masters; verify DECERR B,
  per-beat DECERR R with correct beat count and `32'hDEC0DE00` data.
- `parallel`: fork M0→S0 + M1→S1 simultaneous long bursts (len 15), then
  crossed (M0→S1 + M1→S0); verify no data corruption (disjoint address
  regions per master).
- `contention`: both masters burst-hammer the same slave, disjoint regions;
  verify all data lands + both masters complete (fairness smoke: neither
  starves — both finish 20 bursts each).
- `random`: fork both masters, 60 random legal bursts each over the full map
  including DECERR addresses, disjoint per-master address regions, random IDs;
  model-checked.

## 11. Divergences from full AXI4 (documented scope limits)

Single outstanding transaction per master port per direction; no write
interleaving (AXI4 forbids it anyway); no exclusive access, LOCK/CACHE/QOS/
REGION/USER omitted; no read data interleaving at master ports; slaves respond
in order. These are typical for a lightweight interconnect and are what the
verification plan targets.
