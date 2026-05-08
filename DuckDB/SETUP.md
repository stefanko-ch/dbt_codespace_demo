# DuckDB Tutorial — Setup

This `DuckDB/` folder is a sub-tutorial of the main workshop. The Codespace
environment defined at the repo root (see [`.devcontainer/`](../.devcontainer/))
already provisions everything you need — there is **no separate setup**.

## What's installed automatically

When the Codespace builds, the root [`.devcontainer/post-create.sh`](../.devcontainer/post-create.sh)
script:

1. Builds the dbt project's venv at `dbt/.venv` via `uv sync`.
2. Layers the DuckDB notebook tooling (`jupyterlab`, `jupysql`,
   `duckdb-engine`, `polars`, `pyarrow`, `matplotlib`, `seaborn`,
   `plotly`, ...) into the **same** venv, so a single activation covers
   both dbt and the notebooks.
3. The DuckDB CLI is baked into the Docker image (see
   [`.devcontainer/Dockerfile`](../.devcontainer/Dockerfile)) and is
   available system-wide as `duckdb`.

The dbt venv auto-activates in fresh terminals via `~/.bashrc`.

## Verify the install

```bash
duckdb --version              # CLI
python -c "import duckdb; print(duckdb.__version__)"
python -c "import jupysql, polars, plotly; print('notebook deps ok')"
jupyter --version
```

## Run the notebooks

Open any `.ipynb` under [`Intro/`](Intro/), [`Notebooks/`](Notebooks/),
or [`exercises/`](exercises/) directly in VS Code. When prompted for a
kernel, pick the dbt venv (`dbt/.venv/bin/python`). Port **8888** is
forwarded automatically, so `jupyter lab` from the terminal also works
if you prefer the standalone Jupyter UI.

## Updating dependencies

The notebook dependencies live in [`requirements.txt`](requirements.txt).
After changing them:

```bash
uv pip install -r DuckDB/requirements.txt
```

(Run from the repo root with the dbt venv active.)

## Troubleshooting

### "Module not found" inside a notebook

You're on the wrong kernel. In VS Code: top-right of the notebook → kernel
picker → select `dbt/.venv/bin/python`.

### Jupyter kernel doesn't appear

Register the venv as a named kernel once:

```bash
python -m ipykernel install --user --name=dbt --display-name="dbt + DuckDB"
```

### CLI not found

The DuckDB CLI is installed during the Docker build. If `which duckdb`
returns nothing, rebuild the container (Codespaces: **Rebuild Container**
from the Command Palette).
