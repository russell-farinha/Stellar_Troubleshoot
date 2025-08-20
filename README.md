# Stellar Troubleshoot

A **modular, menu-driven troubleshooting tool** for Stellar Cyber Photon/Ubuntu sensors. This script lets support engineers navigate categories of tools defined in `tools.conf`, view descriptions, and run troubleshooting scripts directly on Linux systems.

---

## Features

- Dynamic category listing based on `tools.conf`
- Alphabetical sorting of tools within each category
- Two-step UI:
  1. **Categories view** – select a category
  2. **Tools view** – select a tool to view details and run it
- Tool detail view with options to **run the tool** or go back
- Integrated search for **tool names** (in Tools mode)
- Compatible with **Photon Linux** and **Ubuntu 22.x**
- Automatic cleanup of downloaded scripts on exit
- Portable key handling with **fractional timeout fallback** (works on BusyBox/older shells that require integer timeouts)

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

3. Ensure `tools.conf` exists in the same directory and follows this format (example provided at the bottom):

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

- `/` – Search tool **names** (Tools mode)

- `q` – Quit and clean up downloaded tools

**Esc + Arrow keys** handling works smoothly on modern bash; on BusyBox/older shells that don’t support sub‑second timeouts, the script automatically falls back to integer timeouts.

---

## Workflow

1. **Select a category** – categories are dynamically loaded from `tools.conf`

2. **Select a tool** – tools are shown alphabetically

3. **Tool detail view** – shows the description and lets you:

    - **Run tool** – downloads and runs the script

    - **Back to tools** – return to the tool list

---

## Configuration: `tools.conf`

- Format: `CATEGORY|NAME|DESCRIPTION|URL`

- Lines starting with `#` are ignored

- Multi-word categories are supported

- Update tools by editing this file (you can keep the same `troubleshooter.sh` on services and only ship an updated `tools.conf`)

**Example:**

```
# CATEGORY|NAME|DESCRIPTION|URL
Mathematics|Addition|Simple 'Addition' script that adds 2 integers|GIST-URL
Mathematics|Subtraction|Simple 'Subtraction' script that subtracts 2 integers|GIST-URL
System Diagnostics|Firewall Check|Netcats required IPs and respective Ports and displays connectivity results|GIST-URL
```