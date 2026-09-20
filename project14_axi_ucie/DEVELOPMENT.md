# Project 14 development status

## Current baseline

- Packaged source is stored in `AXI_UCIe_CoverageGuided_Project14.zip`.
- Python coverage-guidance regression: **3/3 passed locally**.
- GitHub Actions workflow added to repeat the Python regression on pushes and pull requests.
- RTL/UVM/Questa simulation still requires a simulator environment with SystemVerilog/UVM support.

## Next engineering milestones

1. Run full Questa compile/elaboration and fix all simulator-specific issues.
2. Add deterministic smoke tests for AXI read/write, backpressure, reset and error responses.
3. Export machine-readable coverage results from simulation.
4. Feed uncovered bins into the Python UCB1 selector automatically.
5. Add multi-seed regression and convergence plots.
6. Replace the abstract UCIe transport with a compliant UCIe BFM/IP when available.

## Scope boundary

The current UCIe path is an abstract transaction transport for verification research. It is not a claim of complete UCIe PHY or protocol-stack compliance.
