#!/bin/bash
# Install the Verilator version this TB is validated with (pip package, pinned).
# Ubuntu apt Verilator 5.020 mis-runs the full TB (scoreboard mismatch even on
# known-good RTL), so a `verilator` wrapper for the pinned version is put first in PATH.
#
# Usage: bash TB/env/setup_verilator.sh
#   Called by the SessionStart hook in .claude/settings.json (cloud sessions).
#   Idempotent: an existing install of the pinned version is reused.
set -euo pipefail

VERILATOR_VERSION="5.48.0"
INSTALL_DIR="${TRAINING_DMA_TOOLS:-$HOME/.cache/training_2d_dma}/verilator-${VERILATOR_VERSION}"
VENV="$INSTALL_DIR/venv"
WRAPPER_DIR="$INSTALL_DIR/bin"

if ! "$VENV/bin/python" -m pip show verilator 2>/dev/null | grep -qx "Version: ${VERILATOR_VERSION}"; then
    python3 -m venv "$VENV"
    "$VENV/bin/python" -m pip install -q --disable-pip-version-check "verilator==${VERILATOR_VERSION}"
fi

ROOT="$("$VENV/bin/python" -c 'import verilator, pathlib; print(pathlib.Path(verilator.__file__).parent)')"
mkdir -p "$WRAPPER_DIR"
cat > "$WRAPPER_DIR/verilator" <<EOF
#!/bin/sh
export VERILATOR_ROOT="$ROOT"
export CXXFLAGS="\${CXXFLAGS:---std=c++20 -DVL_TIME_CONTEXT}"
exec "$ROOT/bin/verilator" "\$@"
EOF
chmod +x "$WRAPPER_DIR/verilator"

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export PATH=\"$WRAPPER_DIR:\$PATH\"" >> "$CLAUDE_ENV_FILE"
else
    echo "Add to PATH: export PATH=\"$WRAPPER_DIR:\$PATH\""
fi

if ! python3 -c 'import PIL' 2>/dev/null; then
    echo "WARNING: Pillow is missing; TB/env/img2txt.py (IMG_STREAM input) will not run." >&2
fi

"$WRAPPER_DIR/verilator" --version
