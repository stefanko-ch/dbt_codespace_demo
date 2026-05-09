# Task 5 — Sync dbt → Metabase Automatically

**Goal:** replace the manual Metabase curation you did in [Task 4](04-metabase.md) with a single CLI command that propagates descriptions, foreign keys, entity keys, and semantic types **directly from your dbt YAML files**. The end state: dbt is the single source of truth for the semantic layer, Metabase is a projection of it.

Plan to spend ~30 minutes here.

## Why this matters

In Task 4 you built a beautiful curated Metabase model — and we ended on a downer:

- The whole curation lives only in Metabase's own database. Wipe the Codespace and it's gone.
- A colleague who clones the repo gets nothing — they have to do every click again.
- Dbt and Metabase will drift: rename a column upstream, the description stays stale.

The fix: treat dbt's `*.yml` files as the authoritative spec, and let a tool replay them into Metabase whenever needed. The dbt files are version-controlled, code-reviewed, and tested. Metabase becomes regeneratable from them.

That tool is **[`dbt-metabase`](https://github.com/gouline/dbt-metabase)** — actively maintained (v1.7.x as of 2026), open source, production-grade.

## What gets synced

| dbt source                                              | → | Metabase result                            |
| ------------------------------------------------------- | - | ------------------------------------------ |
| `description:` on a model or column                     |   | Table / column description                 |
| `tests: [unique, not_null]` on a key column             |   | Entity Key marker                          |
| `tests: relationships:`                                 |   | Foreign Key target on the column           |
| Column-name conventions (`*_email`, `*_url`, `*_id`)    |   | Inferred semantic types                    |
| `meta:` blocks in YAML (custom)                         |   | Display name overrides, hidden flags, semantic types |

The `meta:` block is the escape hatch — anything that doesn't map cleanly from dbt YAML to Metabase metadata, you can express via custom `meta:` keys.

## Step 0 — Prerequisite

You should already have completed Task 4. Specifically:

- The `analytics` Postgres database is registered in Metabase (under the display name `analytics` — see Task 4 Step 1).
- You're an admin on Metabase.

If you skipped Task 4: stop and do it. The mental model from clicking through each Foreign Key + Entity Key by hand is what makes this CLI's flags interpretable.

`dbt-metabase` is already installed in the workshop venv (it's listed in [`dbt/pyproject.toml`](../dbt/pyproject.toml) so `uv sync` brings it in automatically). Verify:

```bash
dbt-metabase --version
```

## Step 1 — Create a Metabase API key

`dbt-metabase` needs admin-scoped API access to write metadata.

In Metabase: **Admin → Settings → Authentication → API Keys → Create API key**.

| Field      | Value             |
| ---------- | ----------------- |
| Name       | `dbt-metabase`    |
| Group      | **Administrators** |

Click **Create**. Copy the resulting `mb_...` token. **You see it once** — Metabase doesn't show it again.

Treat it like a password. Don't paste it on the command line where it'd land in your shell history. Store it as an env var instead:

```bash
export MB_API_KEY='mb_paste_your_key_here'
```

To make it persistent across new terminals, append the line to `~/.bashrc`:

```bash
echo 'export MB_API_KEY="mb_paste_your_key_here"' >> ~/.bashrc
```

> **Don't commit the key.** It'd give anyone with repo access full admin on your Metabase. The Codespace is throwaway, but the habit matters.

## Step 2 — Compile the dbt manifest

`dbt-metabase` reads `dbt/target/manifest.json` — the JSON snapshot of every model, column, description, test, and tag in your project. dbt regenerates it on every run/build/compile.

To produce a fresh one without re-running models:

```bash
cd dbt
dbt compile --target analytics
```

The manifest now lives at `dbt/target/manifest.json` (~1 MB).

## Step 3 — Run the sync

```bash
dbt-metabase models \
  --manifest-path target/manifest.json \
  --metabase-url http://metabase:3000 \
  --metabase-api-key "$MB_API_KEY" \
  --metabase-database analytics \
  --include-schemas marts
```

Two non-obvious arguments worth flagging:

- **`--metabase-url http://metabase:3000`**, NOT `http://localhost:3000`. `dbt-metabase` runs inside the `workspace` container; from there, `localhost` is the workspace itself. Metabase is reachable via its docker-compose service name `metabase`.
- **`--include-schemas marts`** — skip `staging` and `raw`. Staging is intermediate dbt scaffolding, not BI-ready. (You scoped Metabase to `marts` in Task 4 Step 1 for the same reason.)

Expected output: a list of synced models with the count of fields updated per model. ~5 seconds total.

## Step 4 — Compare with what you did manually

Open Metabase: **Browse data → analytics → marts → fact_sales**.

Look at what's now in place that wasn't before:

| Metabase setting                    | Source in dbt YAML                                      |
| ----------------------------------- | ------------------------------------------------------- |
| Table description                   | `description: '{{ doc("fact_sales_grain") }}'`         |
| `customer_key` → Foreign Key → `dim_customer.customer_key` | `tests: relationships: { to: ref('dim_customer'), field: customer_key }` |
| `customer_id` on `dim_customer` → Entity Key | `tests: [unique, not_null]` |
| Each column tooltip                 | `description:` per column in `*__models.yml` |

If you'd done [Task 4](04-metabase.md) and Task 5 separately, the manual settings would still be there too. `dbt-metabase` is **idempotent and additive** — it doesn't wipe what it doesn't know about, it merges.

But for things it *does* manage (descriptions, FK targets, entity keys), it overwrites. So in practice: keep the source of truth in dbt YAML, and only click in Metabase for things that don't have a dbt equivalent (e.g., dashboards and questions themselves).

## Step 5 — The round trip

This is the payoff. Edit a description in dbt YAML and watch it flow through.

Open [`dbt/models/marts/adventureworks/_adventureworks_marts__models.yml`](../dbt/models/marts/adventureworks/_adventureworks_marts__models.yml) and find an existing description, or add one:

```yaml
- name: dim_customer
  description: "One row per customer; mixes individuals and stores. *** Updated by me in dbt YAML ***"
  columns:
    ...
```

Re-run the sync:

```bash
cd dbt
dbt compile --target analytics
dbt-metabase models \
  --manifest-path target/manifest.json \
  --metabase-url http://metabase:3000 \
  --metabase-api-key "$MB_API_KEY" \
  --metabase-database analytics \
  --include-schemas marts
```

Refresh Metabase, hover the `dim_customer` table name. The new description appears.

That's the whole game: **dbt YAML → CLI → Metabase**. Whenever the model changes, run the two commands. In a real project, you'd put them in a CI pipeline that runs after every successful `dbt build` on main, so Metabase is always in sync without anyone clicking.

## When to fall back to manual curation

`dbt-metabase` covers the common 80%. The remaining 20% still belongs in Metabase's UI:

- **Dashboard layouts** — what cards go where, dashboard filters. dbt has no concept of that.
- **Saved Questions** — the `dbt-metabase exposures` subcommand can extract these BACK into dbt as exposures, but it doesn't push them.
- **Permissions / Collections** — who can see what. Manage in Metabase Admin.
- **Pulses / Subscriptions** — scheduled email or Slack reports.
- **Public links / Embeds** — sharing dashboards externally.
- **One-off ad-hoc descriptions** — sometimes you want a column-level description in Metabase that doesn't belong in a dbt YAML (e.g. a temporary explanation during incident analysis).

Rule of thumb: **if it makes sense to version-control it, put it in dbt YAML and let `dbt-metabase` propagate it.** If it's purely a Metabase-side artefact (a dashboard, a permission), curate in Metabase.

## What `dbt-metabase` does NOT sync

A few traps to be aware of:

- **Numeric semantic types** require explicit `meta:` blocks on the column. Currency vs Percentage isn't auto-detected.
- **Hidden columns** also need `meta: { metabase.visibility_type: "details-only" }` in the YAML.
- **Custom display names** in Metabase's "Override original column name" UI need `meta: { metabase.display_name: "..." }`.

The `meta:` block syntax is documented in the [`dbt-metabase` README](https://github.com/gouline/dbt-metabase). Anything you set manually in Metabase that doesn't have an equivalent in dbt YAML survives the sync — `dbt-metabase` doesn't touch it.

## Acceptance check

```bash
cd dbt
dbt compile --target analytics
dbt-metabase models \
  --manifest-path target/manifest.json \
  --metabase-url http://metabase:3000 \
  --metabase-api-key "$MB_API_KEY" \
  --metabase-database analytics \
  --include-schemas marts
```

Exits with code 0. The output mentions every dim and the fact, with field counts. Metabase shows the same descriptions and FKs you (would have) clicked in Task 4.

## Hands-on exercises

Pick at least one:

1. **Add a column description to `dim_product.color` in dbt YAML** (e.g. *"AdventureWorks color name; a few products have NULL color"*), re-run the sync, verify in Metabase.
2. **Tag your fact and dims with `meta: { metabase.visibility_type: "details-only" }`** on the surrogate `*_key` columns so they hide in normal table views. Sync. See the columns disappear from Browse Data, but stay accessible via "View detail".
3. **Add a `meta:` block on `fact_sales.unit_price_discount`** to set its semantic type to Percentage, sync, watch Metabase format the numbers as `12.5%` instead of `0.125`.
4. **Wire the sync into a post-build hook**. Add to `dbt_project.yml`:
   ```yaml
   on-run-end:
     - "{{ log('Run dbt-metabase models in the shell after this completes', info=True) }}"
   ```
   (Real on-run-end hooks can run arbitrary SQL, not arbitrary shell. To actually trigger `dbt-metabase` after every build, wrap `dbt build && dbt-metabase models …` in a shell script — that's the production pattern.)

## Common issues

| Symptom | Likely cause |
| ------- | ------------ |
| `Got unexpected extra argument (staging)` | Space-separated `--include-schemas marts staging`. Use comma-separated: `--include-schemas marts,staging` (or just `marts` for our case). |
| `Connection refused on localhost:3000` | You used `--metabase-url http://localhost:3000` from inside the workspace container. Use `http://metabase:3000` (the docker-compose service name). |
| `Database not found: analytics` | The Metabase display name doesn't match. Either rename the DB in Metabase Admin → Databases to `analytics`, or pass `--metabase-database <whatever-you-named-it>`. |
| `Authentication failed (401)` | Wrong / expired `mb_...` key, or you used a session token instead of an API key. |
| `Table 'ANALYTICS.MARTS.X' not in schema 'MARTS'` (looping) | Metabase's metadata cache is stale — it last synced when schemas had different names (e.g. `public_marts`). Hit **Sync database schema now** in Admin → Databases → analytics, wait 30 s, retry. |
| Sync runs but Metabase still shows old descriptions | Metabase caches metadata for ~1 hour. Hit **Sync database now** to force a refresh. |
| `dbt-metabase` says "model not found" | Either your `--include-schemas` is wrong, or you forgot `dbt compile` after a model rename. The tool can only see what's in `manifest.json`. |

## Hints

- `dbt-metabase models --help` lists every flag, including `--metabase-exclude-sources`, `--metabase-fk-columns-only`, and friends if you want to scope the sync narrower.
- `dbt-metabase exposures` (different subcommand) goes the *other* direction: exports Metabase questions and dashboards as dbt `exposures:` so dbt knows what's downstream of each model. Useful when you want `dbt source freshness` to flag issues that affect specific dashboards.
- Treat the sync command as part of your dbt CI: `dbt build && dbt-metabase models …` — Metabase is always in sync without manual touch.
- The OSS Metabase API key has no expiry, but if the user account that created it gets deactivated, the key dies with them. In production, create the key under a service account (`dbt-bot@yourcompany.com`).

## Done!

You've now seen both extremes: full manual curation (Task 4) and full automation (Task 5). In real life you'll mix the two — most metadata lives in dbt YAML, a small surface (dashboards, permissions, ad-hoc descriptions) is curated in Metabase.

This pattern is what makes the **dbt + Metabase** combination different from "BI tool + warehouse" — there's a real bridge between the modelling layer and the analytics layer, and it's two CLI commands wide.

→ Back to [Tutorial overview](README.md)
