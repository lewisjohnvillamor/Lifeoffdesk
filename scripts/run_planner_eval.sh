#!/usr/bin/env bash
# Development diagnostic only: runs the app's planner + LlamaEngine against the pinned model
# on this Mac/Linux machine. It does not prove iPhone inference.
# Usage: scripts/run_planner_eval.sh /path/to/llama.cpp-checkout-with-build [extra planner-eval args]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA="${1:?path to a llama.cpp b11429 checkout built with BUILD_SHARED_LIBS=ON}"
shift
MODEL="${MODEL:-$ROOT/downloads/model/Qwen3-1.7B-Q4_K_M.gguf}"
[ -f "$MODEL" ] || { echo "Missing $MODEL; run scripts/download_materials.py --group model-large" >&2; exit 1; }
LIBDIR="$LLAMA/build/bin"
PKG="$ROOT/Tools/PlannerEval"
swift build --package-path "$PKG" -c release -Xcc "-I$LLAMA/include" -Xcc "-I$LLAMA/ggml/include" \
  -Xlinker "-L$LIBDIR" -Xlinker "-rpath" -Xlinker "$LIBDIR"
# Run from the caller's directory so relative --out paths resolve as expected.
"$(swift build --package-path "$PKG" -c release --show-bin-path)/planner-eval" "$MODEL" "$ROOT" "$@"
