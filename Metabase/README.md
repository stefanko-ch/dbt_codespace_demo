# Metabase — Get Comfortable First

Before you dive into [Tutorial 04](../tutorial/04-metabase.md) (where you'll connect Metabase to the warehouse and model the star schema), spend ~30 minutes getting familiar with Metabase itself. The workshop assumes you can already navigate the UI — Questions, Dashboards, Collections, the query builder — and that's exactly what the official, free Metabase tutorials cover.

This README is the lightweight on-ramp: how to log in, what's already running, where to go to learn the basics.

## What's already running in your Codespace

The [`docker-compose.yml`](../.devcontainer/docker-compose.yml) ships a Metabase service that comes up automatically with the rest of the stack. Port **3000** is forwarded — open it from the **Ports** panel at the bottom of VS Code (or the Codespaces UI).

| Service | Port | What it is |
|---|---|---|
| Metabase | 3000 | The BI tool — questions, dashboards, exploration |
| Postgres | 5432 | The warehouse — `analytics`, `playground`, `kestra`, `metabase` databases |
| Kestra   | 8090 | The orchestrator — bronze ingest |
| dbt docs | 8080 | The lineage + model documentation site |

Metabase persists its own data (your account, questions, dashboards) in the `metabase` database on the same Postgres instance. Container restarts don't lose anything; deleting the Codespace does.

## Step 1 — First-time setup

1. Open port **3000**. On first visit, Metabase walks you through:
   - Language → English
   - Admin profile → use any name and email; **pick a password you'll remember** — there's no recovery flow in the OSS version
   - "I'll add my data later" — we connect Postgres in Tutorial 04 deliberately, so just click through
2. You land on the empty Metabase home screen. Bookmark this tab.

## Step 2 — Learn the basics (off-Codespace)

Metabase has a polished free learning hub at [**metabase.com/learn**](https://www.metabase.com/learn/) — short videos and walkthroughs, ~30 minutes total. Work through the **"Getting started"** track:

| Lesson | What you'll come away with |
|---|---|
| Metabase concepts | The mental model: Databases → Questions → Dashboards → Collections |
| Finding data | The Browse Data UI, table search, recently viewed |
| Asking questions | The graphical query builder — Summarize, Filter, Group by |
| Creating dashboards | Adding cards, sizing, parameters |
| Filtering & limiting | Dashboard filters, linked filters, click behavior |
| Summarizing data | Common aggregations, custom expressions |
| Custom columns | Computed fields without leaving the GUI |

You don't need to memorize anything — just see each thing once. When you hit Tutorial 04 you'll recognize the screens; when you hit Tutorial 05 (the dbt-metabase sync) you'll appreciate why automating the manual setup is a win.

> **Sample data:** Metabase ships with a "Sample Database" so you can practice on it without our warehouse being involved. Click around, build a couple of dummy questions and dashboards, get a feel for the UI. We don't care about the dummy work — the muscle memory is the point.

## Step 3 — Worth knowing before Tutorial 04

A few concepts that aren't always obvious from the videos:

- **Question ≠ Dashboard.** A Question is a single saved query (with its visualization). A Dashboard arranges many Questions on a canvas with shared filters.
- **Collections are folders.** Personal vs. shared, with permissions. Useful when many people use the instance; for us a single workshop user, irrelevant.
- **Models** (in Metabase's sense, not dbt's). Metabase calls a curated, semantic-layer table on top of a raw table a "Model". You can build them via SQL or by saving a Question as a Model. Tutorial 04 doesn't use Metabase Models — we let our **dbt** marts be the semantic layer instead, which is the better separation of concerns.
- **The X-Ray button** auto-generates an exploration of any table or column. Fun on the Sample Database, occasionally useful on real data.
- **Drill-through** is the magic that makes a clickable bar chart drop you into the underlying rows. It needs the Foreign Key relationships set up correctly — that's what Tutorial 04 spends most of its time on.

## Next

Once the official tutorial feels comfortable:

→ [Tutorial 04: Connect Metabase to the warehouse and model the star schema](../tutorial/04-metabase.md)

After that, when you're tired of clicking through Admin → Table Metadata:

→ [Tutorial 05: Automate the modeling with dbt-metabase](../tutorial/05-dbt-metabase-sync.md)

Or if you just want a working dashboard without any of the modeling steps — for a demo, or after re-spinning your Codespace:

→ [Pre-built Sales Overview dashboard](dashboard.md) — one Python script, all four questions plus a date-range filter wired up.
