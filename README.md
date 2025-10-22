# Project Orion

Project Orion is a Bash script that provides an interactive menu for running remote diagnostics and helper utilities defined in
`tools.conf`. The first time you run a tool it is downloaded into `./tools/`, and subsequent runs reuse the cached copy or re-
fetch it on demand. The script targets stock Linux distributions and relies only on standard command-line tools that ship with
bash environments.

## Repository layout
- `troubleshooter.sh` – interactive launcher and downloader for Project Orion.
- `tools.conf` – pipe-delimited catalogue of tools grouped by category.
- `tests/run_tests.sh` – historical shell test harness (see [Known limitations](#known-limitations)).

## Requirements
- `bash`
- `curl`
- Standard Unix text utilities (`awk`, `sed`, `sort`, `tr`)
- Optional: `python3` or `python` when executing Python-based tools

## Running the menu
```bash
chmod +x troubleshooter.sh
./troubleshooter.sh
```

The script immediately opens a full-screen menu. Use the keyboard controls below to explore categories, filter tools, and execute
entries.

### Keyboard controls
- `↑` / `↓` – move the highlighted row
- `Enter` – select the highlighted entry
- `b` – return to the previous menu
- `q` – quit without removing cached tools
- `r` – remove cached downloads (`./tools/*`) and exit
- `/` – search tool names and descriptions in the current category
- `n` / `p` – flip to the next or previous results page when pagination is available
- `Ctrl+C` – exit gracefully; cached downloads are removed before quitting

Tool detail pages show the stored description and the runtime that will be used (either Bash or Python).

## Versioning and CLI flags
Project Orion now embeds a semantic version string that is surfaced through the launcher. Use the following commands to inspect
metadata or obtain help without opening the interactive UI:

```bash
./troubleshooter.sh --version
./troubleshooter.sh --help
```

The version constant is defined near the top of `troubleshooter.sh` so downstream consumers can source the script and reuse the
value if needed.

## Tool catalogue format
Each non-comment line in `tools.conf` must contain the following pipe-separated fields:

```
CATEGORY|NAME|DESCRIPTION|URL[|CMD_TEMPLATE|INPUTS_SPEC|RUNTIME|EXTRA...]
```

Only the first four columns are required. When `CMD_TEMPLATE` is omitted the launcher behaves as it always has: the downloaded
script is run directly with either Bash or Python. Specifying `CMD_TEMPLATE` enables argument prompts; a matching
`INPUTS_SPEC` string describes how values are gathered. A runtime override (`bash` or `python`) can still appear in the first
trailing column when no template is present, or after the argument columns when they are used. Any additional metadata columns
(for example a checksum) continue to be ignored.

When the runtime column is omitted entirely, the launcher infers it from the URL extension (`.py` → Python, `.sh` → Bash) and
otherwise defaults to Bash.

Blank lines and comment lines (starting with `#`) are skipped automatically. When running a tool, the script caches it inside
`./tools/<Category>/<Name>.sh` or `.py`, with spaces in the name replaced by underscores.

### Using arguments with `tools.conf`

- `CMD_TEMPLATE` is the exact command line to execute. Use `{script}` as a placeholder for the downloaded tool path and
  `{key}` tokens for each prompted value.
- `INPUTS_SPEC` is a semicolon-delimited list of prompt definitions:
  - `key=value1/value2/...` shows a choice prompt, with the first option used when you press Enter.
  - `key=?Label text` shows a required free-text prompt labelled with `Label text` and loops until a non-blank answer is
    provided.
- All collected answers are shell-escaped and substituted into the template before execution. Tokenisation is handled with
  `python3 -c 'import shlex'` when available and falls back to a simple whitespace split otherwise; no `eval` is ever used.

Example entries:

```
Connectors|Collector Assignments|View/Delete by connector id|https://gist.github.com/.../collector_tool.sh|{script} --action {action} --id {id}|action=view/delete;id=?Connector ID
Networking|Firewall Check|Run port test|https://gist.github.com/.../fw_check.sh|{script} --host {host} --ports {ports}|host=?Target host;ports=?Comma-separated ports
```

Rows that only specify the first four columns continue to work without any prompts.

Blank lines and comment lines (starting with `#`) are skipped automatically. When running a tool, the script caches it inside
`./tools/<Category>/<Name>.sh` or `.py`, with spaces in the name replaced by underscores.

## Downloads and execution
- Downloads use `curl` with a 5-second connect timeout, 60-second overall timeout, and up to three retries on transient failures.
- Cached scripts are reused by default. When a cached copy exists, the launcher prompts you to press `r` to fetch a fresh copy or
accept the cached version.
- Bash tools are marked executable and run directly. Python tools prefer `python3`, falling back to `python` if needed. If neither
interpreter is available, execution is cancelled.

## Known limitations
- `tests/run_tests.sh` predates the current script structure. Because `troubleshooter.sh` launches the menu as soon as it is
sourced, the test harness cannot execute successfully without manual refactoring. Treat the tests as historical reference
material.
- Extra metadata columns in `tools.conf` (such as hashes) are ignored during download; there is no checksum verification.

## Tips for local customization
- Adjust the `PAGE_SIZE`, timeout, and retry settings near the top of `troubleshooter.sh` to fit your environment.
- Add new tools by editing `tools.conf`. Keep URLs commit-pinned when possible so cached scripts stay reproducible.
- To clear the cache without opening the UI, delete the `./tools` directory.
