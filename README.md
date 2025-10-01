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
