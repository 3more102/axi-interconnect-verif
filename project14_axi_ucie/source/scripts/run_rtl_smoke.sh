#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/rtl_smoke"
mkdir -p "$BUILD"
iverilog -g2012 -s rtl_smoke_tb -o "$BUILD/rtl_smoke.vvp"   "$ROOT/rtl/axi_ucie_pkg.sv"   "$ROOT/rtl/axi_ucie_bridge.sv"   "$ROOT/rtl/ucie_responder_model.sv"   "$ROOT/tests/rtl_smoke_tb.sv"
vvp "$BUILD/rtl_smoke.vvp" +STALL_PCT=35 +SEED=20260920
