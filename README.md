# Troubleshooter (Minimal)

A simple, menu‑driven runner for external scripts (Gist/raw URLs).  
This build **always re‑downloads** the tool before execution (no cache prompt).

## Files
- `troubleshooter.sh` — main runner (interactive + `--run` CLI)
- `tools.conf` — 4 columns: `CATEGORY|NAME|DESCRIPTION|URL`

## Usage
```bash
chmod +x troubleshooter.sh
./troubleshooter.sh
```

### Run directly
```bash
./troubleshooter.sh --run --tool "Firewall Check" --category "System Diagnostics"
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

The script follows the standard “test first” loop:

1. Update or add tests that describe the behaviour you need.
2. Run `./tests/run_tests.sh` to watch them fail.
3. Implement the change in `troubleshooter.sh`.
4. Re-run the tests until they pass, then commit your work.

This repository uses a single main script, so the test harness loads it directly. Ensure any new helper functions are safe to source (i.e., keep interactive startup inside the `BASH_SOURCE` guard at the bottom of `troubleshooter.sh`).
