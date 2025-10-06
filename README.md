# Troubleshooter (Minimal)

A simple, menu‑driven runner for external scripts (Gist/raw URLs).  
This build **always re‑downloads** the tool before execution (no cache prompt).

## Files
- `troubleshooter.sh` — main runner (interactive + `--run` CLI)
- `tools.conf` — 4 columns: `CATEGORY|NAME|DESCRIPTION|URL`

## Usage

### Requirements
- `bash`
- `curl`
- Standard Unix text utilities: `awk`, `sed`, `sort`, `tr`

```bash
chmod +x troubleshooter.sh
./troubleshooter.sh
```

### Run directly
```bash
./troubleshooter.sh --run --tool "Firewall Check" --category "System Diagnostics"
```

### Check version

```bash
./troubleshooter.sh --version
```

### Options
- `--config PATH`     Path to `tools.conf` (default: ./tools.conf)
- `--page-size N`     Items per page in menu (default: 8)
- `--run`             Non-interactive mode
- `--tool NAME`       Tool name (exact)
- `--category NAME`   Category filter for --run
- `--quiet`           Suppress non-essential output

## Config format
Each line:
```
CATEGORY|NAME|DESCRIPTION|URL
```

The runtime is inferred from the URL extension:
- `.sh` → runs with `bash`
- `.py` → runs with `python3` (falls back to `python`)

Keep your URLs **commit‑pinned** when possible to avoid unexpected changes.

## Development & Testing

Automated smoke tests cover key behaviours such as runtime detection, menu rendering under `clear` failures, and cached tool execution when the tool itself exits non-zero. Run them locally before opening a pull request:

```bash
./tests/run_tests.sh
```

## Versioning workflow

The project tracks its release number through the `SCRIPT_VERSION` constant near the top of `troubleshooter.sh`. To decide when and how to bump it:

1. **Group changes by user impact.** Bug fixes or documentation-only tweaks can share a patch release (e.g., `1.2.3 → 1.2.4`). Backwards-compatible feature work usually merits a minor bump (`1.2.3 → 1.3.0`), while breaking changes or large rewrites justify a major release (`1.2.3 → 2.0.0`).
2. **Update tests and docs in the same change.** The smoke test suite includes coverage for `--version`; refresh the expected value whenever you increment the constant, and mention notable changes in the README or changelog if present.
3. **Keep commits focused.** Each version bump should include only the modifications that correspond to the new release. Avoid mixing unrelated refactors with a version update so history stays easy to audit.
4. **Tag the release when merging.** After the pull request lands, create a git tag (e.g., `git tag v1.3.0 && git push origin v1.3.0`) so downstream users can pin to a specific revision.

If you're ever unsure which increment is appropriate, ask a maintainer for guidance and err on the side of smaller bumps—you can always ship another patch if needed.

The script follows the standard “test first” loop:

1. Update or add tests that describe the behaviour you need.
2. Run `./tests/run_tests.sh` to watch them fail.
3. Implement the change in `troubleshooter.sh`.
4. Re-run the tests until they pass, then commit your work.

This repository uses a single main script, so the test harness loads it directly. Ensure any new helper functions are safe to source (i.e., keep interactive startup inside the `BASH_SOURCE` guard at the bottom of `troubleshooter.sh`).
