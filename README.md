# Stellar Troubleshoot

A **standalone, menu‑driven debugger** for Stellar Cyber services on Linux (Photon/Ubuntu).
Support engineers maintain a simple `tools.conf` file; each entry points to a script (e.g., a GitHub Gist raw URL). The troubleshooter reads `tools.conf`, shows a navigable menu, and downloads/runs the chosen script locally.

- No external dependencies beyond `bash` and `curl`.

- No environment variables required.

- Pagination, searching (names + descriptions), and a clear footer are built in.

---

## What’s included (current behavior)

- **Dynamic Catalog**
Reads categories and tools from `tools.conf` (pipe‑separated). Multi‑word categories supported. Windows newlines (CRLF) are handled.

- **Alphabetical Tools**
Tools are sorted by name using a locale‑stable sort (`LC_ALL=C`) so ordering is consistent across systems.

- **Pagination**
Hardcoded `PAGE_SIZE=20` with `n`/`p` navigation; footer shows **Results** and **Page** counters.

- **Search (case‑insensitive)**
`/` filters by **tool name and description**. Blank search resets the filter. Search resets to page 1.

- **List shows description**
Tools are shown as `Name — Description` in the Tools list.

- **Reload (`r`)**

    - In **Categories**: reloads `tools.conf` and repopulates the category list.

    - In **Tools**: reloads the current category’s tools (preserves the category selection and resets pagination).

- **Two‑step UI**
Categories → Tools → Tool Detail (with Run/Back).

- **Download retries & simple cache**
`curl` uses timeouts/retries. If the same tool was already downloaded during the session, you’re prompted to reuse the cached copy or re‑download.

- **Safe colors**
Gracefully disables color if `tput`/terminal don’t support it.

- **Ctrl‑C behavior**
Immediately cleans up downloaded scripts, clears the screen, and exits with code **130**. (No lingering loop.)

- **Quit**
`q` also cleans up and exits.

---

## Requirements

- **Bash** (default on Photon/Ubuntu)

- **curl**

- Network access to the raw URLs in your `tools.conf`

---

## Installation

```bash
# Put these two files together
./troubleshooter.sh
./tools.conf

chmod +x ./troubleshooter.sh
```

---

## Usage

```bash
./troubleshooter.sh
```

### Keybindings

- **Arrow Up/Down**: Move selection

- **Enter**: Select item

- **b**: Back (from Tool Detail → Tools, or Tools → Categories)

- **q**: Quit (cleans temporary downloads)

- **Ctrl‑C**: Quit immediately (cleans temporary downloads, exit code 130)

- **n** / **p** (Tools view): Next/Prev page

- **/** (Tools view): Search (name + description). Blank input resets the filter.

- **r**:

    - **Categories view**: Reload categories from `tools.conf`

    - **Tools view**: Reload tools for the current category

### Footer & Counters

- In **Tools** view you’ll see:
`Results: <match_count> Page: <current>/<total>`
This updates automatically as you search or paginate.

---

## Workflow

1. **Pick a category** (from `tools.conf`)

2. **Pick a tool** (list shows `Name — Description`, alphabetically)

3. **Tool Detail** shows the description and lets you:

    - **Run tool**: downloads the script and executes it

    - **Back to tools**

When running a tool:

- If a same‑session cached copy exists, you’ll be asked: **use cached** or **re‑download**.

- On successful run, you’ll see the exit status; press Enter to return.

- On failure to download, a clear message is shown; press Enter to return.

On exit (via `q` or Ctrl‑C), temporary downloads under `./tools/<Category>/` are removed.

---

## `tools.conf` format

**Minimum 4 columns**, pipe‑separated:

```ini
CATEGORY | NAME | DESCRIPTION | URL
```

- Lines starting with `#` are ignored.

- Whitespace is trimmed.

- Categories and names can contain spaces.

- **Descriptions appear in the list view**, so keep them concise (ideally < 80 characters) for better readability in typical terminal widths.

**Example (matches your current structure)**

```ini
# CATEGORY|NAME|DESCRIPTION|URL
General Sensor Tools|Addition|Simple 'Addition' script that adds 2 integers|https://.../option1.sh
Connectors|Subtraction|Simple 'Subtraction' script that subtracts 2 integers|https://.../option2.sh
System Diagnostics|Firewall Check|Netcats required IPs and respective Ports and displays connectivity results|https://.../firewall_checks.sh
# (You can keep duplicates here for testing if you like.)
```

**Tip**: Use **commit‑pinned** raw URLs for scripts. Updating a tool = publish new revision and update just that line in `tools.conf`.

---

## Customization (hardcoded settings)

At the top of `troubleshooter.sh`:

```bash
PAGE_SIZE=20       # Tools per page
CONNECT_TIMEOUT=5  # curl connect timeout (seconds)
MAX_TIME=60        # curl overall timeout (seconds)
DOWNLOAD_RETRIES=3 # curl retries on transient failures
```

Adjust these numbers directly in the script if needed. No env vars are required or used.

---

## Output, caching, and cleanup details

- **Download location**: `./tools/<Category>/<Name_with_underscores>.sh`

- **Cache reuse prompt**: If the file already exists and is executable, you can reuse it or force a re‑download.

- **Cleanup**: On `q` or Ctrl‑C, `./tools/*` is deleted and the screen is cleared.

---

## Troubleshooting

- **Arrow keys don’t work reliably on some shells**
The script uses a tiny timeout after `Esc` to read arrow sequences. If a shell doesn’t support sub‑second timeouts, it falls back to an integer timeout. This may feel slightly less snappy, but it’s portable.

- **Long descriptions wrap**
The list shows `Name — Description` per line. If descriptions are too long for your terminal width, you may see wrapping. Keep descriptions short for the cleanest UI.

- **Download failures**
The script uses `curl` with connect/overall timeouts and automatic retries. If a URL is unreachable, you’ll see a clear error and can try again.

---

## License

MIT

---

## Changelog (recent)

- Added **pagination** with `n`/`p` and footer counters

- **Search** now matches **names and descriptions**

- Tools list shows Name — Description

- Added **reload** `r` in **Categories** (reloads categories) and **Tools** (reloads tools for current category)

- **Ctrl‑C** now exits immediately (cleanup + clear + code 130)

- **curl** hardened with timeouts/retries; added session **cache reuse** prompt

- Colors now **degrade gracefully** if `tput`/terminal lack color support

- Sorting is **locale‑stable** for consistent ordering everywhere