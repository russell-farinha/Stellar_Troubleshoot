# Stellar Troubleshoot

A **modular, menu-driven troubleshooting tool** for Stellar Cyber Photon sensors. This script allows users to easily navigate categories of tools, view descriptions, and run troubleshooting scripts directly on Photon-based Linux environments.

---

## Features

- Dynamic category listing based on `tools.conf`
- Alphabetical sorting of tools within each category
- Two-step UI:
  1. **Categories view** – select a category
  2. **Tools view** – select a tool to view details and run it
- Dynamic help guide at the bottom of the screen based on context
- Tool description view with options to **run the tool** or return to the previous menu
- Integrated search for tool names in tools mode
- Fully compatible with **Photon Linux** and other Linux distributions
- Automatic cleanup of downloaded scripts after exit

---

## Requirements

- **Bash** (default on Photon Linux)
- **curl** (for downloading scripts)
- Ubuntu 22.x or Photon Linux environment
- Network access to URLs defined in `tools.conf`

---

## Installation

1. Clone this repository:

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
General Sensor Tools|Addition|Simple 'Addition' script that adds 2 integers|https://example.com/addition.sh
Connectors|Subtraction|Simple 'Subtraction' script that subtracts 2 integers|https://example.com/subtraction.sh
```

## Usage

Run the troubleshooter script:

```bash
./troubleshooter.sh
```

## Navigation

* `↑/↓` – Move up/down through menu options

* `Enter` – Select highlighted option

* `b` – Go back (only available in Tools and Tool Detail modes)

* `/` – Search tool names (only in Tools mode)

* `q` – Quit and clean up downloaded tools

## Workflow

1. **Select a category** – categories are dynamically loaded from `tools.conf`

2. **Select a tool** – only the tool names are shown alphabetically

3. **Tool detail view** – displays description and gives options:

    * **Run tool** – executes the script

    * **Back to tools** – returns to tool list

## Configuration (`tools.conf`)

* Format: `CATEGORY|NAME|DESCRIPTION|URL`

* Lines starting with `#` are ignored

* Example:

```
# CATEGORY|NAME|DESCRIPTION|URL
General Sensor Tools|Addition|Adds two numbers|https://example.com/addition.sh
Connectors|Subtraction|Subtracts two numbers|https://example.com/subtraction.sh
System Diagnostics|Firewall Check|Checks connectivity to IP:PORT|https://example.com/firewall_check.sh
```

* Multi-word categories are fully supported

* Tools can be added, removed, or updated by editing this file

## Cleanup

All downloaded scripts are stored temporarily in `./tools` and automatically deleted on quit.

## Contributing

1. Fork the repository

2. Make your changes

3. Update `tools.conf` if necessary

4. Submit a pull request

## License

MIT License

## Notes

* Ensure network connectivity for downloading tool scripts

* Tested on Photon Linux and Ubuntu 22.x

* Supports dynamically adding/removing categories and tools via `tools.conf`