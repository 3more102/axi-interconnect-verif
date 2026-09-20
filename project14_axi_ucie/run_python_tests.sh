#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIP="$ROOT/AXI_UCIe_CoverageGuided_Project14.zip"
WORK="$ROOT/.project14_work"

rm -rf "$WORK"
mkdir -p "$WORK"
unzip -q "$ZIP" -d "$WORK"

cd "$WORK/AXI_UCIe_CoverageGuided"
python -m pytest -q

echo "Project 14 Python verification passed."
