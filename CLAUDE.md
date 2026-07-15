# Project Orion — CLAUDE.md

## What this is

Project Orion is a menu-driven troubleshooting CLI for Stellar Cyber environments: a single Bash file (`troubleshooter.sh`) plus a collection of tool scripts, organized by the CATEGORY column of a pipe-delimited catalog (`tools.conf`).

The single-file architecture is a **deliberate choice**, not tech debt. Do not restructure into modules, add build steps, or change the catalog format unless explicitly asked. Changes should stay minimal and self-contained.

## Repo layout

| Path | Purpose |
| --- | --- |
| `troubleshooter.sh` | The interactive launcher (single file, Bash 4+) |
| `tools.conf` | Pipe-delimited tool catalog: `CATEGORY\|NAME\|DESCRIPTION\|SOURCE[\|RUNTIME\|EXTRA]` |
| `scripts/` | Locally hosted (vendored) tool scripts |
| `tools/` | Runtime cache for downloaded (remote-URL) tools — disposable; never deleted by the UI, remove manually if needed |
| `releases/` | Tarball releases |

## Hard constraints

1. **No shell escape, ever.** Orion runs in customer environments behind a restricted CLI shim. No feature may let a user run arbitrary shell commands from the UI. Any tool that invokes `less` must run with `LESSSECURE=1`.
2. **Dependency-free.** Bash 4+, `curl`, `awk`, `sed`, standard POSIX tools only. Optional `python3`/`python` for Python tools. No new dependencies.
3. **Doc-sync rule.** Every behavior-changing commit updates `README.md` **and** this `CLAUDE.md` in the same commit.
4. **No file deletion from the UI.** No UI action may delete files — there is no cleanup key, and the quit paths (`q`, Ctrl-C) must not remove anything. Refreshing a cached remote tool happens only through the per-tool re-download prompt, which overwrites that tool's own cache file.
5. **Version bumps.** Any user-visible behavior change bumps `VERSION` in `troubleshooter.sh` and the version in `README.md`.

## Development workflow (multi-instance, iterative)

Feature work on this repo uses two Claude instances with the human (Russell) as the relay:

1. **Design session** — a Claude session designs the feature and produces a self-contained build prompt with explicit requirements, constraints, and acceptance criteria.
2. **Builder session** — a *separate* Claude instance receives that prompt and implements it:
   - Create a feature branch off `main` (e.g. `feature/<name>`). Never commit directly to `main`.
   - Commit locally. **Do not push** — pushing happens only after review and manual testing pass.
   - Follow the doc-sync rule (README.md + CLAUDE.md in the same commit).
   - Verify syntax (`bash -n troubleshooter.sh`, `shellcheck` if available) before finishing.
   - End with a summary: files touched, decisions made, any deviations from the spec.
3. **Review** — back in the design session, review the diff (`git diff main...feature/<name>`) against the spec.
4. **Manual test** — Russell runs the manual test checklist provided by the design session and reports results.
5. **Iterate** — repeat steps 2–4 (builder fixes, design session re-reviews, Russell re-tests) until the checklist passes clean.
6. **Ship** — the design session drafts the push/PR/merge commands; Russell runs them. GitHub flow: push the feature branch, open a PR, merge to `main`.

## Manual testing baseline

Before shipping any change to `troubleshooter.sh`, verify at minimum:

- `./troubleshooter.sh --help` and `--version` print correctly and exit 0.
- Menu navigation: arrows, Enter, `b`, `n`/`p` pagination, `/` search.
- A local-path tool runs without any download or cache prompt.
- A remote-URL tool still downloads, caches, and offers the cached/re-download prompt.
- A tool that requires arguments receives them correctly.
- `q` and Ctrl-C exit without deleting anything: `./tools/` and `scripts/` are untouched afterward.
