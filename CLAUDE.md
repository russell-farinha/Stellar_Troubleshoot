# Project Orion — CLAUDE.md

## What this is

Project Orion is a menu-driven troubleshooting CLI for Stellar Cyber environments: a single Bash file (`troubleshooter.sh`) plus a collection of tool scripts, organized by a catalog the launcher builds at startup from self-describing header comments in each script under `scripts/`.

The single-file architecture is a **deliberate choice**, not tech debt. Do not restructure into modules, add build steps, or change the header format unless explicitly asked. Changes should stay minimal and self-contained.

## Repo layout

| Path | Purpose |
| --- | --- |
| `troubleshooter.sh` | The interactive launcher (single file, Bash 4+) |
| `scripts/` | Tool scripts (`*.sh`, `*.py`); each carries an `# orion:begin` ... `# orion:end` header that defines its catalog entry. Files starting with `_` or `.` are ignored. Symlinks are ignored (`--check` WARN). Symlinked `scripts/` or `scripts/temp/` directories are unsupported (nothing listed, `--check` WARN). Header values must not contain 0x1f (ERROR in regular tier, stripped in temp). Tool and category sorting is case-insensitive; categories differing only in case merge (`--check` WARN). A CRLF shebang line on a bash tool is a `--check` WARN (not for Python) |
| `scripts/temp/` | Temporary (emergency) scripts; always listed under Temporary with `[TEMP]`, header optional |
| `scripts/_template.sh`, `scripts/_template.py` | Copy these to start a new tool (not listed in the menu) |
| `releases/` | Tarball releases |

## Hard constraints

1. **No shell escape, ever.** Orion runs in customer environments behind a restricted CLI shim. No feature may let a user run arbitrary shell commands from the UI. Any tool that invokes `less` must run with `LESSSECURE=1`.
2. **Dependency-free.** Bash 4+, `awk`, `sed`, standard POSIX tools only. Optional `python3`/`python` for Python tools. No new dependencies.
3. **Doc-sync rule.** Every behavior-changing commit updates `README.md` **and** this `CLAUDE.md` in the same commit.
4. **No file deletion from the UI.** No UI action may delete files — and the quit paths (`q`, Ctrl-C) must not remove anything.
5. **Version bumps.** Any user-visible behavior change bumps `VERSION` in `troubleshooter.sh` and the version in `README.md`.
6. **Arguments prompt is data, not shell.** The "Arguments (optional)" input is split on whitespace honoring single and double quotes only. It must never be passed to `eval`, expanded (`$VAR`, globs, `~`), or subjected to command substitution.

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
- `./troubleshooter.sh --check` prints OK/WARN/ERROR/TEMP per file; exits 0 only when every file is OK, 1 otherwise.
- A script in `scripts/temp/` appears under Temporary with a `[TEMP]` prefix.
- A header value containing `|` renders correctly in the list and detail screens.
- A tool receives arguments with quotes correctly (e.g. `"a b" c` is two args), and `$(...)` / `$VAR` stay literal.
- `q` and Ctrl-C exit without deleting anything: `scripts/` is untouched afterward.
- A symlink in `scripts/` is ignored (WARN in `--check`) and never chmod'ed or run; EOF on stdin (`printf '' | ./troubleshooter.sh`) exits 0 quickly without a redraw loop.

## Emergency (temporary) scripts fast lane

For a script that must ship before it can be documented:

1. Branch off `main` (e.g. `feature/<name>`); never commit to `main`.
2. Drop the file in `scripts/temp/` (header optional; defaults apply).
3. Syntax check (`bash -n` or `python3 -m py_compile`) and do a quick manual run of that script from the menu.
4. Bump the patch version (`VERSION` + `README.md`) and ship with the normal ACPS package.
5. In the next release, promote it: add a full header and move it out of `temp/`.

The doc-sync rule still applies to the commit.
