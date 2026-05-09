#!/usr/bin/env bash
# Runs once when the Codespace / devcontainer is first built.
# 1. Installs the dbt project's venv via uv (dbt-core + adapters).
# 2. Layers the DuckDB notebook tooling (jupyter, jupysql, polars, plotly, ...)
#    into the SAME venv so users only ever activate one environment.
# 3. Wires up bashrc so a fresh terminal lands in the dbt venv.
set -euo pipefail

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
DBT_VENV="$WORKSPACE/dbt/.venv"

echo "==> Installing dbt project deps (uv sync)"
cd "$WORKSPACE/dbt"
uv sync

if [ -f "$WORKSPACE/DuckDB/requirements.txt" ]; then
    echo "==> Layering DuckDB notebook deps into dbt venv"
    VIRTUAL_ENV="$DBT_VENV" uv pip install --quiet -r "$WORKSPACE/DuckDB/requirements.txt"
fi

echo "==> Wiring dbt venv into ~/.bashrc"
ACTIVATE_LINE="source $DBT_VENV/bin/activate"
grep -qF "$ACTIVATE_LINE" /root/.bashrc 2>/dev/null \
    || echo "$ACTIVATE_LINE" >> /root/.bashrc

echo "==> post-create complete"
