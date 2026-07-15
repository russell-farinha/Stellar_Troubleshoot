---
name: acps-sha
description: Build the Orion delivery package for ACPS — a release tarball plus its .sha1 checksum file — to hand to Alex on the DP team. Use when Russell says Orion is ready for ACPS, asks for "the sha for Alex", or wants a release package after a merge.
---

# ACPS delivery package (tarball + SHA-1)

## Context

Once a change to Project Orion is merged to `main`, Russell delivers **two files** to Alex on the DP team, who pulls them into ACPS:

1. `orion-YYYY_MM_DD_HH_MM.tar.gz` — project files at the **archive root** (no wrapper directory)
2. `orion-YYYY_MM_DD_HH_MM.tar.gz.sha1` — `shasum -a 1` output with the **bare filename**, so Alex can verify with `shasum -c`

Both land in the local `releases/orion-<stamp>/` directory — which is **gitignored**, so releases are recorded via local `v<stamp>` git tags, not commits. The deliverable is NOT a git commit SHA.

## Steps

1. Build from clean, merged, pulled main — never from a feature branch or dirty tree:

   ```bash
   git checkout main && git pull origin main && git status
   ```

   If `git status` shows uncommitted changes or unpushed commits, stop and surface that.

2. Stamp and package. Include `troubleshooter.sh`, `tools.conf`, `README.md`, and `scripts/`. Exclude `CLAUDE.md`, `.claude/`, `tools/` (runtime cache), and `releases/` itself:

   ```bash
   STAMP=$(date +%Y_%m_%d_%H_%M)
   mkdir -p "releases/orion-$STAMP"
   tar -czf "releases/orion-$STAMP/orion-$STAMP.tar.gz" --uid 0 --gid 0 \
       troubleshooter.sh tools.conf README.md scripts
   ```

   (`--uid 0 --gid 0` matches the root-owned entries in prior releases; bsdtar syntax — on GNU tar use `--owner=0 --group=0`.)

3. Generate the checksum **from inside the release directory** so the .sha1 records the bare filename:

   ```bash
   cd "releases/orion-$STAMP"
   shasum -a 1 "orion-$STAMP.tar.gz" > "orion-$STAMP.tar.gz.sha1"
   ```

4. Verify before handing over:

   ```bash
   shasum -c "orion-$STAMP.tar.gz.sha1"   # must print: orion-<stamp>.tar.gz: OK
   tar -tzf "orion-$STAMP.tar.gz"         # confirm expected contents, no wrapper dir
   ```

5. Deliver both files to Alex, e.g.:

   > Orion release for ACPS pull.
   > Package: orion-<stamp>.tar.gz
   > SHA-1: <hash from the .sha1 file>
   > Verify with: shasum -c orion-<stamp>.tar.gz.sha1
   > (<one-line summary of what's in this delivery>)

6. `releases/` is **gitignored** — do NOT commit the release artifacts. Instead, record what was shipped with a local date-stamp tag, matching prior deliveries (`v2025_10_15_09_00`, `v2025_11_04_09_00` are local-only tags):

   ```bash
   git tag "v$STAMP" main
   ```

## Guardrails

- The .sha1 must contain the bare filename (no path) — generate it from within the release directory.
- Never package from a feature branch or an unpushed/stale main.
- If the tarball is ever rebuilt, regenerate the .sha1 — the pair must always match (`shasum -c` proves it).
