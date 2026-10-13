#!/bin/bash
# orion:begin
# name: Template Tool
# category: Platform
# runs_on: any
# mode: read-only
# args: <optional hint>
# description: One-line description of what this tool does
# orion:end
#
# ORION HEADER GUIDE (this text is outside the begin/end block and is ignored)
#   Copy this file to scripts/<your_tool>.EXT, edit the header above, and delete this guide if you like.
#   Files whose name starts with "_" (like this template) are NOT listed by Orion.
#   Orion only reads lines between "# orion:begin" and "# orion:end", within the first 40 lines of the file.
#
#   name         (required) Menu label.
#   category     (required) One of: Connectors, Reporting, Data & Elasticsearch, Platform.
#                Category = the component/problem domain being investigated, not action type or risk.
#   runs_on      (required) Where to run it. Vocabulary: DL-master, DA-master, sensor, "pod: <name>", off-box, any.
#   mode         (required) read-only or changes-state.
#                  changes-state = can modify the platform under diagnosis (services, config, data).
#                  read-only     = does not; it may write its own output/temp files (say so in the description).
#   args         (optional) Hint text shown to the user at the arguments prompt.
#   description  (required) One line, single-line value.
#   runtime      (optional) bash or python; inferred from the file extension if absent.
#   Values are single-line and trimmed; no | restriction applies - any characters fine.

echo "Hello from the Orion shell template"
