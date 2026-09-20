# Project 14 — Coverage-Guided Intelligent Verification Framework for AXI over UCIe Interconnect

This folder contains the packaged graduation-project starter for Project 14.

## Included
- AXI4-Lite to 128-bit abstract transaction-flit bridge RTL
- UVM verification environment
- SystemVerilog Assertions (SVA)
- Functional/semantic coverage
- UCIe-style abstract remote endpoint model with backpressure/error injection
- Python UCB1 coverage-guided scenario selector
- Questa regression scripts
- Verification plan, architecture, proposal, demo plan, references
- Python selector tests (3/3 passed)

## Package
Download and extract `AXI_UCIe_CoverageGuided_Project14.zip`.

## Validation status
Python coverage-guide tests: **3/3 passed**.

SystemVerilog/UVM compile was **not run in the generation environment because Questa was not installed**. Run the supplied scripts in a Questa/UVM environment before treating the RTL/UVM baseline as simulator-validated.

## Scope
The UCIe side is an abstract verification transport. This project does **not** claim full UCIe PHY/protocol compliance. Replace the abstraction with a compliant UCIe IP/BFM when available.
