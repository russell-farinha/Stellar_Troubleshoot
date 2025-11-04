# Project Orion 1.1.0

Project Orion is a self-contained Bash launcher that presents an interactive, keyboard-driven menu for running remote diagnostic
and helper utilities. Tools are defined in `tools.conf`, grouped by category, and fetched on demand into a local cache. Reusing
the cached copy avoids repeat downloads, while a built-in refresh option lets you grab updated scripts when needed.

## Highlights
- **Dependency-light:** requires only `bash`, `curl`, and standard POSIX utilities already present on common Linux distributions.
- **Dynamic catalogue:** reads categories, descriptions, and download URLs directly from `tools.conf` at runtime.
- **Smart runtime detection:** honours an explicit runtime column or infers Bash vs. Python from the tool's file extension.
- **Search & pagination:** filter by keyword inside a category and browse large lists with next/previous page shortcuts.
- **Safe caching:** downloads land in `./tools/<Category>/<Tool>` with spaces replaced by underscores; cleanup commands remove
  cached files in one step.

## Repository contents
- `troubleshooter.sh` – the interactive launcher script.
- `tools.conf` – pipe-delimited configuration that lists available tools.

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
| `q` | Quit without touching cached downloads |
| `r` | Remove cached downloads and exit |
| `Ctrl+C` | Exit gracefully (also clears cached downloads) |

Tool detail screens display the description pulled from `tools.conf` plus the runtime the launcher will use when executing the
script.

## Command-line flags
Project Orion exposes its metadata without launching the UI:

```bash
./troubleshooter.sh --help     # Usage information
./troubleshooter.sh --version  # Prints "Project Orion 1.1.0"
```

## Configuring `tools.conf`
Each non-comment, non-empty line uses the following schema:

```
CATEGORY|TOOL NAME|DESCRIPTION|DOWNLOAD_URL[|RUNTIME|EXTRA...]
```

- `CATEGORY`, `TOOL NAME`, `DESCRIPTION`, and `DOWNLOAD_URL` are required.
- `RUNTIME` is optional. When set to `bash` or `python` it overrides automatic detection.
- Additional columns are ignored by the current implementation, allowing you to stash checksums or notes for future use.

Lines beginning with `#` are treated as comments and skipped. When a tool is executed it is saved to
`./tools/<Category>/<Tool_Name>.<ext>`; the extension is derived from the original download URL.

## Download behaviour
- `curl` is used for transfers with a 5-second connect timeout, 60-second total timeout, and three retry attempts.
- Python tools are executed with `python3` when available, otherwise the launcher falls back to `python`. If neither interpreter
  is present the run is aborted with a warning.
- Re-running a tool that is already cached prompts you to accept the existing copy or press `r` to refresh it.

## Customising the experience
Tweak the constants near the top of `troubleshooter.sh` to adjust pagination size, download timeouts, and retry counts. Removing
the `./tools` directory (or pressing `r` inside the UI) clears the cache. To add new diagnostics, append entries to `tools.conf`
and commit them alongside the script so the catalogue stays reproducible.
