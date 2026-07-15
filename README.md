# Project Orion 1.2.0

Project Orion is a self-contained Bash launcher that presents an interactive, keyboard-driven menu for running diagnostic
and helper utilities. Tools are defined in `tools.conf`, grouped by category, and sourced either from a local path inside the
repository (no network required) or from a remote URL fetched on demand into a local cache. Reusing the cached copy avoids
repeat downloads, while a built-in refresh option lets you grab updated scripts when needed.

## Highlights
- **Dependency-light:** requires only `bash`, `curl`, and standard POSIX utilities already present on common Linux distributions.
- **Offline-capable:** tools vendored under `scripts/` run in place with no download, so sensors without network access can run
  every bundled tool.
- **Dynamic catalogue:** reads categories, descriptions, and tool sources directly from `tools.conf` at runtime.
- **Smart runtime detection:** honours an explicit runtime column or infers Bash vs. Python from the tool's file extension.
- **Search & pagination:** filter by keyword inside a category and browse large lists with next/previous page shortcuts.
- **Safe caching:** downloads land in `./tools/<Category>/<Tool>` with spaces replaced by underscores; no UI action ever
  deletes files — refresh a cached tool via the re-download prompt when running it.

## Repository contents
- `troubleshooter.sh` – the interactive launcher script.
- `tools.conf` – pipe-delimited configuration that lists available tools.
- `scripts/` – locally hosted (vendored) tool scripts, executed in place.

## Getting started
```bash
chmod +x troubleshooter.sh
./troubleshooter.sh
```

By default the script opens the full-screen menu immediately. Use the keyboard shortcuts below to drive the interface:

| Key | Action |
| --- | --- |
| `↑` / `↓` | Move the selection cursor |
| `Enter` | Activate the highlighted row |
| `b` | Back up to the previous view |
| `n` / `p` | Flip between paginated result pages |
| `/` | Search within the current category |
| `q` | Quit |
| `Ctrl+C` | Exit gracefully |

Neither exit removes any files.

Tool detail screens display the description pulled from `tools.conf`, the runtime the launcher will use when executing the
script, and the source — `Source: local (<path>)` or `Source: remote (<url>)`.

## Command-line flags
Project Orion exposes its metadata without launching the UI:

```bash
./troubleshooter.sh --help     # Usage information
./troubleshooter.sh --version  # Prints "Project Orion 1.2.0"
```

## Configuring `tools.conf`
Each non-comment, non-empty line uses the following schema:

```
CATEGORY|TOOL NAME|DESCRIPTION|SOURCE[|RUNTIME|EXTRA...]
```

- `CATEGORY`, `TOOL NAME`, `DESCRIPTION`, and `SOURCE` are required.
- `SOURCE` is either a remote URL (starts with `http://` or `https://`) or a local path relative to the launcher's working
  directory (e.g. `scripts/dump_by_day.sh`). Absolute paths and paths containing `..` are rejected at run time.
- `RUNTIME` is optional. When set to `bash` or `python` it overrides automatic detection (which infers from the source's file
  extension).
- Additional columns are ignored by the current implementation, allowing you to stash checksums or notes for future use.

Lines beginning with `#` are treated as comments and skipped. When a remote tool is executed it is saved to
`./tools/<Category>/<Tool_Name>.<ext>`; the extension is derived from the original download URL.

## Source behaviour
### Local paths
- Local tools run in place from their configured path — no download, no copy into `./tools/`, and no cached-copy prompt.
- If the file is missing or empty, the launcher shows an error and returns to the menu; nothing is executed.

### Remote URLs
- `curl` is used for transfers with a 5-second connect timeout, 60-second total timeout, and three retry attempts.
- Re-running a tool that is already cached prompts you to accept the existing copy or press `r` to refresh it.

For both source types, Python tools are executed with `python3` when available, otherwise the launcher falls back to `python`.
If neither interpreter is present the run is aborted with a warning.

## Customising the experience
Tweak the constants near the top of `troubleshooter.sh` to adjust pagination size, download timeouts, and retry counts. The UI
never deletes files; to clear the download cache, remove the `./tools` directory manually from the shell, or use the
re-download prompt to refresh an individual cached tool. To add new diagnostics, append entries to `tools.conf` and commit them
alongside the script so the catalogue stays reproducible.
