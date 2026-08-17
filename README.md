# AXI4 / AXI4-Lite Interconnect — RTL + Verification

A 2-master × 2-slave AXI crossbar in two flavours (AXI4-Lite and full AXI4 with
bursts and ID routing), each with an internal DECERR default slave, verified by
four independent checking nets: reference-model scoreboards, passive protocol
checkers, BFM self-checks, and unbounded formal property proofs.

Everything is plain **Verilog-2001** RTL and a deliberately restricted testbench
subset, so the same sources run under both Icarus Verilog and ModelSim ASE.
No UVM, no SVA in the testbenches, no vendor IP.

---

## What is here

| Path | Contents |
|---|---|
| `rtl/` | 4 synthesizable modules: two interconnects, two slave devices |
| `tb/` | 2 BFMs, 2 passive protocol checkers, 1 coverage collector, 4 testbenches |
| `sim/` | Icarus flow: filelists, `Makefile`, `report.sh`; ModelSim `.do` + driver |
| `formal/` | SymbiYosys harnesses and property sets |
| `mutation/` | bug-injection catalogue and runner |
| `docs/` | `SPEC.md` (authoritative contract), `VERIF_PLAN.md`, `MUTATION_RESULTS.md` |

### RTL

- **`axi4_lite_interconnect`** — 2×2 AXI4-Lite crossbar. Per-destination
  registered round-robin arbitration; a write grant is held from AW capture
  through the B handshake, a read grant from AR capture through the R handshake.
  Independent read and write paths, so M0→S0 runs concurrently with M1→S1.
- **`axi4_interconnect`** — the same topology for full AXI4: bursts, per-beat
  data, and ID routing. Slave-side IDs are `{master_index, master_id}`;
  responses are steered back by the ID's top bit. The write grant is held
  through WLAST (AXI4 has no WID, so W cannot be interleaved), and each master
  port's R return mux locks to one source per burst until RLAST.
- **`axi4_lite_slave`** — 16-register file, SLVERR above `NUM_REGS`.
- **`axi4_mem_slave`** — 4 KB memory, FIXED/INCR/WRAP bursts, narrow transfers,
  per-beat SLVERR above `MEM_BYTES`.

Address map (both interconnects), decoded on `addr[31:12]`:

| Range | Target |
|---|---|
| `0x0000_0000 – 0x0000_0FFF` | slave port M0 |
| `0x0000_1000 – 0x0000_1FFF` | slave port M1 |
| anything else | internal default slave → **DECERR**, read data `0xDEC0DE00` |

---

## Verification

Four nets check the design independently. A test passes only if **all** of them
report zero errors *and* the test's own sequencing completed — the watchdog
firing is a failure, not a pass.

1. **Scoreboards.** Each testbench carries a reference model of the slaves it
   drives and predicts every response code and every data beat. Byte lanes are
   only compared once the test has written them.
2. **Protocol checkers** (`tb/axi4_protocol_checker.v`,
   `tb/axi4_lite_protocol_checker.v`). Passive monitors on every interface,
   zero tolerance, 13 numbered rules: VALID/payload stability per channel
   (PC01–PC05), X/Z hygiene (PC06–PC07), WLAST position (PC08), per-ID RLAST
   position (PC09), WRAP legality (PC10), the 4 KB rule (PC11), reset behaviour
   (PC12), and unsolicited write responses (PC13). Their outstanding-transaction
   tracking is bounded, and *overflowing that bound is itself reported*, so a
   checker can never go quietly blind.
3. **BFM self-checks.** The master BFMs verify BID/RID reflection and RLAST
   position independently of the scoreboard.
4. **Formal.** Unbounded proofs over the interconnects' ports — see below.

### Functional coverage

35 bins (burst type × direction, transfer size, INCR and WRAP length classes,
response codes, and a burst landing exactly on offset `0xFFF`), collected on the
memory-slave interface and on both interconnect slave ports.

### Running it

```bash
cd sim && make regress
```

Builds all four testbenches, runs the full matrix, and prints a result table,
per-run and union coverage, and a `REGRESSION: N/M PASSED` line. Exit status is
non-zero if any run fails — including a run that produced no verdict at all.

```bash
cd sim && make run TB=tb_axi4_interconnect TEST=random SEED=7 DUMP=1
```

Single run with waves. `make synth` elaborates all four RTL modules in Yosys.

The same sources run under ModelSim ASE as a second simulator:

```powershell
cd sim\modelsim; .\run_modelsim.ps1
```

---

## Results

Measured on Icarus Verilog 12.0, ModelSim ASE 10.5b, and Yosys 0.68.

| Tier | Result |
|---|---|
| Regression (Icarus) | **28/28 runs PASS** — 24 distinct tests, the 4 random tests rerun at a second seed |
| Regression (ModelSim ASE) | **28/28 runs PASS** — identical sources, second simulator |
| Functional coverage | **35/35 bins hit** across the regression union (100%) |
| Mutation audit | **14/14 injected defects killed**, 0 survivors |
| Yosys elaboration | clean on all 4 RTL modules |
| Formal — AXI4-Lite interconnect | **5/5 property groups proven unboundedly** |
| Formal — AXI4 interconnect | reset and ID routing proven unboundedly |

Per-testbench test lists are in [`docs/VERIF_PLAN.md`](docs/VERIF_PLAN.md); the
mutation table and the three holes it exposed are in
[`docs/MUTATION_RESULTS.md`](docs/MUTATION_RESULTS.md).

### Mutation audit

```bash
cd mutation && ./run_mutations.sh
```

Fourteen single-line defects, applied one at a time to a scratch copy of the
RTL; each must be caught by at least one test. The harness runs the clean tree
first (so a "kill" can never be a pre-existing failure), hashes the RTL before
and after each edit (so a `sed` that matches nothing is reported rather than
counted), and reads verdicts from files rather than pipes.

The first pass scored 11/14. All three survivors were real gaps:

- an off-by-one on the memory's write range hid behind a *second* out-of-range
  beat in every straddle test — the check's resolution was coarser than the
  defect;
- breaking the arbiter's round-robin update was invisible to the contention
  test, because with single-outstanding masters the priority pointer is only
  consulted on a genuine tie and no test created one;
- removing reset gating from a master-port READY was invisible everywhere,
  because the spec only constrains VALID during reset.

Closing them added the `fairness` test, two boundary bursts, and a stronger
formal reset property. Three of the fourteen mutations exist to check the
**formal tier itself** — a prover that only ever prints PASS proves nothing.

### Formal property tier

SymbiYosys in `prove` mode with the `abc pdr` engine — unbounded proofs, not
bounded model checking. The harnesses are **black boxes**: they assert only on
DUT ports, so the properties state the interconnect's contract rather than
mirroring its implementation, and `rtl/` carries no embedded assertions.

```bash
cd formal && sby -f lite_ic.sby   # reset, decode, stable, outstanding, worder
cd formal && sby -f ic.sby        # reset, decode, idroute
```

Proven for the AXI4-Lite interconnect:

- **reset** — every DUT-driven VALID is low throughout reset.
- **decode** — an address forwarded to M0 is always in S0's range and one
  forwarded to M1 always in S1's range. No transaction can reach the wrong slave.
- **stable** — every DUT-driven channel holds VALID with a stable payload until
  READY. This is PC01–PC05 proven for all time rather than sampled.
- **outstanding** — one outstanding write and one outstanding read per master
  port, enforced by the DUT's own READY output, plus no response to a master
  with nothing in flight.
- **worder** — a W beat is never pushed to a destination with no AW pending
  there, and the AW/W imbalance stays bounded.

Proven for the full AXI4 interconnect: **reset**, and **idroute** — whenever a
response is consumed from a slave port it is delivered in the same cycle to
exactly the master its ID's top bit names, carrying that master's original ID
and the slave's payload unchanged. `idroute` needs no environment assumptions
at all; it is a property of the DUT's mux alone.

The environment is constrained only to what AXI actually requires: masters hold
VALID with a stable payload until READY and are single-outstanding; slaves
answer only transactions they accepted, in order, reflecting the ID they were
given. Everything else — addresses, data, READY timing, response codes — is
left free, so a proof covers every legal traffic pattern rather than a sampled
subset. The assumptions are written out and commented in the harness files.

---

## Scope limits

These are deliberate, documented in `docs/SPEC.md` §11, and are what the
verification targets:

- One outstanding transaction per master port per direction.
- No write-data interleaving (AXI4 forbids it anyway) and no read-data
  interleaving at a master port.
- Slaves respond in order.
- `LOCK`, `CACHE`, `QOS`, `REGION` and `USER` are omitted entirely; no exclusive
  access.
- Both interconnects capture AW into a holding register and then forward it, so
  a master's first AW is always accepted and it stalls at the arbiter rather
  than at the AW handshake. The externally observable property — a master cannot
  push a write through a destination another master holds, and M0→S0 runs
  concurrently with M1→S1 — is preserved, and the crossbar-concurrency testbench
  check asserts that distinct paths really were active in the same cycle rather
  than assuming it.

## Requirements

Icarus Verilog 12.0, Yosys 0.68, SymbiYosys with ABC, GNU make. ModelSim ASE is
optional. No SMT solver is required: the formal flow uses `abc pdr` and sets
`aigsmt none`, so a genuine failure is reported as a failure rather than as a
tool error.

## License

MIT — see [LICENSE](LICENSE).
