# Project 14 — Coverage-Guided Intelligent Verification Framework for AXI over UCIe Interconnect

This folder contains the Project 14 graduation-project implementation.

## Current structure

- `AXI_UCIe_CoverageGuided_Project14.zip` — original packaged baseline.
- `source/` — unpacked Phase-2 working source used by CI.
- `DEVELOPMENT.md` — engineering roadmap.

## Implemented baseline

- AXI4-Lite to 128-bit abstract transaction-flit bridge RTL.
- Abstract UCIe-style remote endpoint with memory, backpressure and deterministic error region.
- UVM environment, scoreboard, functional coverage and SVA in the packaged baseline.
- Python UCB1 coverage-guided scenario selector.
- Questa-oriented adaptive regression flow.

## Phase-2 improvements

The active `source/` tree adds:

- deterministic xorshift32 responder stalls controlled by `+SEED`;
- an independent non-UVM RTL smoke test;
- tests for AW-before-W and W-before-AW channel ordering;
- full and partial-strobe memory writes;
- response backpressure;
- SLVERR error-window checking;
- `protocol_error` sanity checking;
- expanded coverage-guide unit tests from 3 to **6**;
- GitHub Actions jobs for both Python tests and Icarus-Verilog RTL simulation.

Run locally on Linux:

```bash
cd project14_axi_ucie/source
python -m pytest -q tests/test_coverage_guide.py
bash scripts/run_rtl_smoke.sh
```

## Validation status

- Python unit tests: **6/6 pass locally**.
- GitHub Actions validates the same Python suite.
- RTL smoke simulation is now validated in CI with Icarus Verilog.
- Full UVM/Questa compile and regression remain a separate milestone because they require a Questa/UVM environment.

## Scope boundary

The UCIe side is an abstract verification transaction transport. It is not a claim of complete UCIe PHY, link-layer, or protocol-stack compliance. A compliant UCIe BFM/IP should replace this abstraction in the later integration phase.
