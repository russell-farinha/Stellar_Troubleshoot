# Project Orion 1.4.0

Project Orion is a self-contained Bash launcher that presents an interactive, keyboard-driven menu for running diagnostic
and helper utilities. The catalogue is built at startup by scanning the scripts under `scripts/` for a small self-describing
header comment, so adding a tool means adding one file. Everything runs in place from the repository; no network is required
by the launcher.

## Highlights
- **Dependency-light:** the launcher requires only `bash` 4+, `awk`, `sed`, and standard POSIX utilities. Individual tools may
  have their own prerequisites (for example `curl` or Python).
- **Offline-capable:** every tool runs in place from `scripts/`.
- **Self-describing catalogue:** categories, descriptions, run location, and risk mode come from each script's header.
- **Smart runtime detection:** honours an optional `runtime` header field or infers Bash vs. Python from the file extension.
- **Search & pagination:** filter by keyword inside a category and browse large lists with next/previous page shortcuts.
- **Node-aware:** hides tools that only apply to a different node type (DA, DL, sensor), with a safe override (see "Node filter").
- **Safe by design:** no UI action ever deletes files, and the arguments prompt never runs shell expansion.

## Repository contents
- `troubleshooter.sh` – the interactive launcher script.
- `scripts/` – tool scripts, executed in place; each carries a header that defines its catalogue entry.
- `scripts/temp/` – Temporary (emergency) scripts; see below.
- `scripts/_template.sh`, `scripts/_template.py` – starting points for new tools (not listed in the menu).

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
| `t` | Cycle the node filter (categories and tool-list screens): auto, da, dl, sensor, all |
| `q` | Quit |
| `Ctrl+C` | Exit gracefully |

Neither exit removes any files.

Tool detail screens display the description, category, where the tool runs (`runs_on`), its mode, the argument hint (if any),
the runtime the launcher will use, and the source path (`Source: local (<path>)`). A `changes-state` mode is shown in a
warning colour before the Run prompt.

## Command-line flags
Project Orion exposes its metadata without launching the UI:

```bash
./troubleshooter.sh --help     # Usage information
./troubleshooter.sh --version  # Prints "Project Orion 1.4.0"
./troubleshooter.sh --check    # Validate script headers and exit
./troubleshooter.sh --node dl  # Start with the node filter set (da, dl, sensor, or all)
```

`--check` prints one line per scanned file (`OK`, `WARN`, `ERROR`, or `TEMP` with a short reason), then the categories in
use and a summary. It exits 0 only when every scanned file is OK; any WARN, ERROR, or TEMP gives exit status 1.

## Node filter
Orion runs on on-prem/pre-SaaS Stellar nodes. It shows only the tools that apply to the node it is running on, using each
tool's free-text `runs_on` header (no header change). The active node is shown under the title (for example
`Node: dl (auto: aella_role)`), and the tool list says `N tool(s) hidden for this node - press t to change` when something
is hidden. Categories with no visible tools are not listed.

**Choosing the node** (first match wins):
1. `--node <da|dl|sensor|all>` (a bad or missing value prints an error and usage, exit 1).
2. `ORION_NODE=<da|dl|sensor|all>` (an invalid value is ignored with a warning and detection is used).
3. Auto-detect, read-only (no sudo, kubectl, or network): the value of `aella_role:` in
   `/opt/aelladata/work/da_conf.yml`. A role of `dl` (optionally followed by `-<suffix>`, e.g. `DL-master`) means DL; a role of `da` or `dr`
   (optionally followed by `-<suffix>`, e.g. `DR-master`, which a DA master has been seen as) means DA. Any other or empty value, or an unreadable/missing file, means `unknown`.
   That file also exists on DL nodes and may exist on non-DP boxes, so only the role value counts.

`all` and `unknown` do no filtering. Press `t` to cycle auto, da, dl, sensor, all, and back to auto (which re-runs detection).
There is no reliable automatic signal for sensors, so sensors are override-only (`--node sensor`, `ORION_NODE=sensor`, or `t`).
The hostname is only a hint: if it starts with `da-`/`da_` or `dl-`/`dl_` and the node is `unknown`, the header says
"hostname suggests dl" but nothing is filtered on it. For testing, `ORION_DA_CONF` overrides the da_conf.yml path.

**Matching `runs_on`:** the value is lowercased and split on commas, slashes, and whitespace. Recognized tokens:

| Token | Node |
| --- | --- |
| `da`, `da-master`, `da-vm`, `da-worker` | da |
| `dl`, `dl-master`, `dl-vm`, `dl-worker` | dl |
| `sensor` | sensor |
| `any` | every node |

Anything else (`in-pod`, `off-box`, `not specified`, free text) is ignored. A tool is hidden only when the active node is
da, dl, or sensor and the tool lists at least one recognized node, does not list `any`, and does not list the active node.
A tool with no recognized token is always shown. Temporary tools follow the same rules. If the filter would hide every tool
it is ignored (with a notice). `--check`, search, and tool detail are unaffected by the filter.

## Script headers
The launcher reads a comment block within the first 40 lines of each script (works for `.sh` and `.py`):

```
# orion:begin
# name: Find Connector Pod
# category: Connectors
# runs_on: DA-master
# mode: read-only
# args: <connector_id>
# description: Locate the log-collector pod that runs a connector
# orion:end
```

- Only lines between `# orion:begin` and `# orion:end` count. Keys are case-insensitive; values are single-line, trimmed, and
  may contain any character, including `|`.
- **Required:** `name`, `category`, `description`, `runs_on`, `mode`. **Optional:** `args` (hint shown at the arguments
  prompt), `runtime` (`bash` or `python`; inferred from `.sh` / `.py` if absent).
- `mode` is `read-only` or `changes-state`. `changes-state` means the tool can modify the platform under diagnosis
  (services, config, data). `read-only` means it does not; it may still write its own output or temp files (say so in the
  description).
- `runs_on` is free text. Recommended vocabulary: `DL-master`, `DA-master`, `sensor`, `pod: <name>`, `off-box`, `any`. Node tokens in this value drive the node filter (see above).

### Categories
Categories come from valid headers and are listed alphabetically (case-insensitively; spellings that differ only in case merge into one entry and `--check` warns), with Temporary always last. Tools are also sorted case-insensitively. A category names the component
or problem domain being investigated (currently Connectors, Reporting, Data & Elasticsearch, Platform) — never the action
type or risk; where it runs and its mode are attributes, not categories.

### Which files are scanned
`scripts/*.sh` and `scripts/*.py`, plus `scripts/temp/*.sh|*.py`. Files starting with `_` or `.`, other extensions, other
subdirectories, and `__pycache__` are ignored. A script without an `orion:begin` marker is skipped silently at launch
(`--check` reports WARN); a script with a marker but a missing/empty required field or an invalid `mode` is also skipped
(`--check` reports ERROR naming the problem).
Symlinks are ignored (`--check` reports WARN "symlink ignored") so nothing outside `scripts/` is listed or run. Symlinked `scripts/` or `scripts/temp/` directories are not supported: nothing is listed from them and `--check` warns. A header value
may not contain the ASCII unit-separator control character (0x1f): in the regular tier that is an ERROR, in `temp/` it is
stripped. A bash script whose first line ends in CR (CRLF line endings) gets a `--check` WARN because it will fail to run (Python tools are not affected).

### Temporary lane
Scripts in `scripts/temp/` are always listed under the category **Temporary**, with a `[TEMP]` prefix, even with no header.
Missing fields default to: name = filename without extension (underscores become spaces), description = `Temporary script -
no documentation yet`, `runs_on` and `mode` = `not specified`. A valid header overrides the defaults (except category). The
detail screen warns that the script is temporary and has not been documented or reviewed for a release. To promote one, add a
full header and move it out of `temp/`.

## Adding a tool
1. Copy `scripts/_template.sh` or `scripts/_template.py` to `scripts/<your_tool>.<ext>`.
2. Fill in the header (see above) and replace the body.
3. Run `./troubleshooter.sh --check` to confirm it shows OK, and commit the script.

## Running tools
Local tools run in place — no download, copy, or cache. If the file is missing or empty, the launcher shows an error and returns
to the menu; nothing is executed. Python tools are executed with `python3` when available, otherwise `python`; if neither is
present the run is aborted with a warning.

The "Arguments (optional)" prompt splits your input on whitespace, honouring single and double quotes. It never expands
variables or globs and never runs command substitution, so `$(...)` and `$VAR` are passed through literally.

## Customising the experience
Tweak the constants near the top of `troubleshooter.sh` to adjust pagination size. The UI never deletes files.
