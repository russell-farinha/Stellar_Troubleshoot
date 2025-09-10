# Stellar Troubleshoot

A **standalone, menu-driven debugger** for Stellar Cyber services on Linux (Photon/Ubuntu).

Support engineers maintain a simple `tools.conf`; each entry points to a script (e.g., a GitHub Gist raw URL). The troubleshooter reads `tools.conf`, shows a navigable menu, and downloads/runs the chosen script locally.

- Minimal dependencies: **bash**, **curl**, and (optionally) **python** for Python tools.
- No environment variables required.
- Pagination, search (names + descriptions), runtime auto-detection, and a clear footer are built in.

---

## Features

- **Dynamic Catalog**  
  Reads categories and tools from `tools.conf` (pipe-separated). Multi-word categories supported. Windows newlines (CRLF) are handled.

- **Alphabetical Tools**  
  Tools are sorted by name using a locale-stable sort (`LC_ALL=C`) so ordering is consistent across systems.

- **Pagination**  
  Hardcoded `PAGE_SIZE=5` with `n`/`p` navigation. Footer shows **Results** and **Page** counters.

- **Search (case-insensitive)**  
  `/` filters by **tool name and description**. Blank search resets the filter. Search resets to page 1.

- **List shows description**  
  Tools appear as `Name — Description` in the Tools list.

- **Reload (`r`)**  
  In **Categories** or **Tools**, pressing `r` cleans up downloaded scripts and quits.

- **Two-step UI**  
  Categories → Tools → Tool Detail (with Run/Back). Tool Detail shows the Description and **Runtime** (bash/python).

- **Runtime auto-detection (Bash & Python)**  
  - If the URL ends with `.sh`, the tool runs with **bash**.  
  - If the URL ends with `.py`, the tool runs with **python** (`python3` preferred, then `python`).  
  - (Optional) If a **5th column** in `tools.conf` is present and equals `bash` or `python`, that explicit value overrides the URL inference.

- **Download retries & simple cache**  
  `curl` uses timeouts/retries (no `--retry-all-errors` for old curl). If the same tool was already downloaded during the session, you’re prompted to reuse the cached copy or re-download.

- **Safe colors**  
  Gracefully disables color if `tput`/terminal don’t support it.

- **Ctrl-C behavior**  
  Immediately cleans up downloaded scripts, clears the screen, and exits with code **130**.

- **Quit**  
  `q` exits immediately **without cleanup**.  
  `r` performs cleanup **and** quits.

---

## Requirements

- **bash**, **curl**
- **python3** (or **python**) only if you intend to run Python tools
- Network access to the raw URLs in `tools.conf`

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
- **q**: Quit immediately (no cleanup)
- **r**: Cleanup downloaded tools and quit
- **Ctrl-C**: Cleanup downloaded tools and quit (exit code 130)
- **n / p** (Tools view): Next/Prev page
- **/** (Tools view): Search (name + description). Blank input resets the filter.

### Footer & Counters

- In **Tools** view you’ll see:  
  `Results: <match_count>  Page: <current>/<total>`  

---

## Workflow

1. **Pick a category** (from `tools.conf`)  
2. **Pick a tool** (`Name — Description`, alphabetically)  
3. **Tool Detail** shows the Description and **Runtime**. Choose:
   - **Run tool** → downloads and runs it (bash or python)
   - **Back to tools**

When running a tool:
- If a same-session cached copy exists, you’ll be asked: **use cached** or **re-download**.
- On success, you’ll see the exit status; press Enter to return.
- On download failure, a clear message is shown; press Enter to return.

On exit (`q`, `r`, or Ctrl-C), behavior differs:  
- `q` quits immediately, no cleanup.  
- `r` and **Ctrl-C** perform cleanup of `./tools/*` and quit.

---

## `tools.conf` format

**Minimum 4 columns**, pipe-separated:

```
CATEGORY | NAME | DESCRIPTION | URL
```

- Lines starting with `#` are ignored.
- Whitespace is trimmed.
- Categories and names can contain spaces.
- **Descriptions appear in the list view**, so keep them concise.

### (Optional) 5th column to pin runtime

You can add a 5th column with an explicit runtime:

```
CATEGORY | NAME | DESCRIPTION | URL | RUNTIME
```

Where `RUNTIME` is `bash` or `python`. This overrides URL-based detection.

**Examples**

```ini
# 4 columns, runtime inferred from URL:
General Sensor Tools|Addition|Adds two numbers|https://.../option1.sh
System Diagnostics|Firewall Check|Netcat to IP:PORT|https://.../firewall_checks.sh
# Python tool by URL:
Analytics|Gather Inventory|Collect basic system info|https://.../inv_collector.py

# 5th column overrides (optional):
Analytics|Gather Inventory (Py)|Collect basic system info|https://.../inv.sh|python
SRE|Rotate Logs|Rotate service logs safely|https://.../rotate.py|bash
```

> **Tip:** Use **commit-pinned** raw URLs for scripts. Updating a tool = publish new revision and update just that line in `tools.conf`.

---

## Customization (hardcoded settings)

At the top of `troubleshooter.sh`:

```bash
PAGE_SIZE=5        # Tools per page
CONNECT_TIMEOUT=5  # curl connect timeout (seconds)
MAX_TIME=60        # curl overall timeout (seconds)
DOWNLOAD_RETRIES=3 # curl retries on transient failures
```

Adjust these numbers directly in the script if needed.

---

## Output, caching, and cleanup

- **Download location:** `./tools/<Category>/<Name_with_underscores>.sh|.py`
- **Cache reuse prompt:** If the file already exists and is non-empty, you can reuse it or re-download.
- **Cleanup:**  
  - On `q`: no cleanup (files remain).  
  - On `r` or **Ctrl-C**: `./tools/*` is deleted and the screen is cleared.

---

## Troubleshooting

- **Python not found**  
  If a Python tool is selected and neither `python3` nor `python` is available, the runner will explain and return to the menu.

- **Arrow keys on older shells**  
  The script uses a small timeout after `Esc` to read arrow sequences. If sub-second timeouts aren’t supported, it falls back to a 1-second integer timeout for portability.

- **Long descriptions wrap**  
  The list shows `Name — Description`. Very long descriptions may wrap based on terminal width.

- **Download failures**  
  `curl` has connect/overall timeouts and retries. If a URL is unreachable, you’ll see a clear error and can try again.

---

## Security note (quick)

- You are executing remote scripts by design. Keep code review discipline on `tools.conf` and the referenced scripts.
- If you later want integrity checks (e.g., SHA-256 per tool), we can add an optional column and verify downloads before execution—no workflow disruption.

---

## License

MIT
