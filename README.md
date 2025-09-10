# Stellar Troubleshoot

A **modular, menu‑driven troubleshooting tool** for Stellar Cyber Photon/Ubuntu sensors. This script lets support engineers navigate categories of tools defined in `tools.conf`, view descriptions, and run troubleshooting scripts directly on Linux systems.

---

## Features

- Dynamic category listing based on `tools.conf`
- Alphabetical sorting of tools within each category
- Two‑step UI:
  1. **Categories view** – select a category
  2. **Tools view** – select a tool to view details and run it
- Tool detail view with options to **run the tool** or go back
- Integrated search for **tool names** (in Tools mode)
- Compatible with **Photon Linux** and **Ubuntu 22.x**
- Automatic cleanup of downloaded scripts on exit
- Portable key handling with a **fractional timeout fallback** (works on BusyBox/older shells that require integer timeouts)

> Note: This project targets **Linux**. A Windows/PowerShell sibling may be built later.

---

## Requirements

- **Bash**
- **curl** (for downloading scripts)
- Photon Linux or Ubuntu 22.x
- Network access to the URLs defined in `tools.conf`

---

## Installation

1. Clone the repository:

    ```bash
    git clone https://github.com/yourusername/stellar-troubleshoot.git
    cd stellar-troubleshoot
    ```

2. Make the script executable:

    ```bash
    chmod +x troubleshooter.sh
    ```

3. Ensure `tools.conf` exists in the same directory and follows this format:

    ```
    # CATEGORY|NAME|DESCRIPTION|URL
    ```

---

## Usage

Run the troubleshooter:
```bash
./troubleshooter.sh
```

---

## Navigation

- `↑/↓` – Move up/down

- `Enter` – Select highlighted option

- `b` – Back (available in Tools and Tool Detail modes)

- `/` – Search tool **names** (Tools mode; **blank search resets filter**)

- `q` – Quit and clean up downloaded tools

**Esc + Arrow keys** handling works smoothly on modern bash; on BusyBox/older shells that don’t support sub‑second timeouts, the script automatically falls back to integer timeouts.

---

## Workflow

1. **Select a category** – categories are dynamically loaded from `tools.conf`

2. **Select a tool** – tools are shown alphabetically

3. **Tool detail view** – shows the description and lets you:

    - **Run tool** – downloads and runs the script

    - **Back to tools** – return to the tool list

## Configuration: `tools.conf`

- Format: `CATEGORY|NAME|DESCRIPTION|URL`

- Lines starting with `#` are ignored

- Multi‑word categories are supported

- Update tools by editing this file (you can keep the same `troubleshooter.sh` on services and only ship an updated `tools.conf`)

Example (aligned with default categories):

```
# CATEGORY|NAME|DESCRIPTION|URL
General Sensor Tools|Addition|Simple 'Addition' script that adds 2 integers|GIST-RAW-URL
Connectors|Subtraction|Simple 'Subtraction' script that subtracts 2 integers|GIST-RAW-URL
System Diagnostics|Firewall Check|Netcats required IPs and respective Ports and displays connectivity results|GIST-RAW-URL
```

---

## Cleanup

All downloaded scripts are stored temporarily under `./tools/<Category>` and automatically deleted on quit (and on Ctrl‑C).

---

## Contributing

1. Fork the repository

2. Make your changes

3. Update `tools.conf` if necessary

4. Submit a pull request

## Compatibility

This tool is designed to be portable across Stellar Cyber platforms.

### Baseline Tested Environment (Data Processor: Ubuntu 16.04.7 LTS)

- **OS**: Ubuntu 16.04.7 LTS (xenial)
- **Bash**: 4.3.48(1)-release (x86_64-pc-linux-gnu)
- **Curl**: 7.47.0 (with GnuTLS 3.4.10, zlib 1.2.8, libidn 1.32, librtmp 2.3)
- **Python**: 3.5.2 (required only for `.py` tools)
- **Awk**: GNU Awk 4.1.3, API 1.1 (MPFR 3.1.4, GMP 6.1.0)
- **Sed**: GNU sed 4.2.2
- **Coreutils**:
  - sort (GNU coreutils) 8.25
  - tr (GNU coreutils) 8.25
- **Terminal**: ANSI/`tput` supported (falls back gracefully if not available)

### Notes

- Python is **only required for Python tools**; bash-only tools run without Python installed.
- The script avoids modern curl flags (e.g., `--retry-all-errors`) for compatibility with curl 7.47.0 (Ubuntu 16.04 default).
- For consistent results, descriptions in `tools.conf` should remain short (< 80 chars) to avoid wrapping in narrow terminal sessions.


## License

MIT License