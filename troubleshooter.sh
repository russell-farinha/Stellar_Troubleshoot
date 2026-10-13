#!/usr/bin/env bash
#
# Project Orion
# Modular, menu-driven tool for remote diagnostics
# Ubuntu/Photon, dependency-free (bash; optional python)
#
# The tool catalog is built at startup from header comments in scripts/*.sh|*.py
# (regular tier) and scripts/temp/*.sh|*.py (Temporary tier).
#

SCRIPTS_DIR="scripts"
APP_NAME="Project Orion"
VERSION="1.3.0"

# Hardcoded settings (no ENV needed)
PAGE_SIZE=5                  # Tools per page
HEADER_SCAN_LINES=40         # Header must sit within the first N lines
TEMP_CATEGORY="Temporary"
US=$'\x1f'                   # Internal field separator; header values containing it are rejected (regular tier) or stripped (temp tier)
ALL_FILTER="${US}all"        # Sentinel for the "All tools" category filter

# Colors (graceful fallback if tput/TERM unsupported)
BOLD=""; RESET=""; CYAN=""; YELLOW=""; GREEN=""; RED=""
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    if [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
        BOLD=$(tput bold); RESET=$(tput sgr0)
        CYAN=$(tput setaf 6); YELLOW=$(tput setaf 3)
        GREEN=$(tput setaf 2); RED=$(tput setaf 1)
    fi
fi

# Globals
MENU_OPTIONS=()
MENU_ACTIONS=()
CURSOR=0
MODE="categories"  # categories | tools | tool_detail
SELECTED_CATEGORY=""
SELECTED_IDX=-1           # index into the SC_* catalog arrays

# Catalog (parallel arrays, one entry per scanned script)
SC_FILE=(); SC_STATUS=(); SC_MSG=(); SC_LISTED=(); SC_TEMP=()
SC_NAME=(); SC_CAT=(); SC_RUNS=(); SC_MODE=(); SC_ARGS=(); SC_DESC=(); SC_RUNTIME=()
SEARCH_TERM=""
CURRENT_PAGE=0
TOTAL_PAGES=0
VISIBLE_COUNT=0

# Ctrl-C exits cleanly (never deletes anything)
trap 'echo; echo "${YELLOW}Exiting (Ctrl-C)...${RESET}"; clear; exit 130' INT

# Tiny-timeout feature detection (some shells reject fractional -t)
supports_subsecond_read() {
    { IFS= read -r -t 0.01 _ 2>/dev/null <<<""; } && return 0 || return 1
}
if supports_subsecond_read; then
    READ_TINY_TIMEOUT=(-t 0.05)   # ~50ms lookahead for escape sequences
else
    READ_TINY_TIMEOUT=(-t 1)      # integer seconds only (BusyBox/older)
fi

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# --- Source handling ---------------------------------------------------------
# Tools are local scripts under ./scripts, resolved relative to the current
# working directory and executed in place. Paths must stay inside the working
# directory: no absolute paths, no ".." path component, no symlinks (checked on
# the file and every parent component). Names such as "a..b.sh" are fine.
validate_local_source() {
    local p="$1" comp acc="" rest
    case "$p" in
        /*) return 1;;
    esac
    rest="$p"
    while [[ -n "$rest" ]]; do
        comp="${rest%%/*}"
        if [[ "$rest" == */* ]]; then rest="${rest#*/}"; else rest=""; fi
        [[ -z "$comp" || "$comp" == "." ]] && continue
        [[ "$comp" == ".." ]] && return 1
        acc="${acc:+$acc/}$comp"
        [[ -L "$acc" ]] && return 1
    done
    return 0
}

# --- Header scanner ----------------------------------------------------------
# Header format (within the first HEADER_SCAN_LINES lines):
#   # orion:begin
#   # name: ...          (required)
#   # category: ...      (required)
#   # runs_on: ...       (required, free text)
#   # mode: read-only|changes-state   (required)
#   # description: ...   (required)
#   # args: ...          (optional hint)
#   # runtime: bash|python (optional; inferred from extension)
#   # orion:end
# Emits one line, fields separated by US (0x1f):
#   state name category runs_on mode args description runtime ctl
# ctl: 1 if any value contained US itself (it is stripped from the values).
# state: 0 = no begin marker, 1 = complete header, 2 = begin without end.
parse_header() {
    awk -v max="$HEADER_SCAN_LINES" '
    function trim(x) { sub(/^[ \t]+/, "", x); sub(/[ \t]+$/, "", x); return x }
    BEGIN { st = 0; ctl = 0 }
    NR > max { exit }
    {
        line = $0; sub(/\r$/, "", line)
        if (st == 0) {
            if (tolower(line) ~ /^[ \t]*#[ \t]*orion:begin[ \t]*$/) st = 2
            next
        }
        if (tolower(line) ~ /^[ \t]*#[ \t]*orion:end[ \t]*$/) { st = 1; exit }
        if (match(line, /^[ \t]*#[ \t]*[A-Za-z_]+[ \t]*:/)) {
            key = substr(line, 1, RLENGTH)
            val = substr(line, RLENGTH + 1)
            sub(/^[ \t]*#[ \t]*/, "", key); sub(/[ \t]*:$/, "", key)
            key = tolower(key)
            if (index(val, "\037") > 0) { ctl = 1; gsub("\037", "", val) }
            if (!(key in v)) v[key] = trim(val)
        }
    }
    END {
        US = "\037"
        printf "%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n", st, US, v["name"], US, v["category"], US, \
            v["runs_on"], US, v["mode"], US, v["args"], US, v["description"], US, v["runtime"], US, ctl
    }' "$1"
}

# Scan one file and append it to the SC_* arrays.
# $1 = path, $2 = 1 if Temporary tier, 0 otherwise
scan_one() {
    local f="$1" is_temp="$2"
    local st name cat runs mode args desc rt ctl
    IFS="$US" read -r st name cat runs mode args desc rt ctl < <(parse_header "$f")

    # CRLF shebang line breaks execution ("bad interpreter")
    local first="" crlf=0
    IFS= read -r first < "$f" || true
    [[ "$first" == *$'\r' ]] && crlf=1

    local base="${f##*/}" ext rt_default
    ext="$(lower "${base##*.}")"
    [[ "$ext" == "py" ]] && rt_default="python" || rt_default="bash"

    local mode_lc rt_lc
    mode_lc="$(lower "$mode")"
    rt_lc="$(lower "$rt")"

    local mode_ok=0 rt_ok=0
    [[ "$mode_lc" == "read-only" || "$mode_lc" == "changes-state" ]] && mode_ok=1
    [[ -z "$rt_lc" || "$rt_lc" == "bash" || "$rt_lc" == "python" ]] && rt_ok=1

    local status msg listed=0
    if (( is_temp )); then
        local stem="${base%.*}"
        local missing=()
        local f_name="${stem//_/ }" f_desc="Temporary script - no documentation yet"
        local f_runs="not specified" f_mode="not specified" f_args="" f_rt="$rt_default"
        if [[ "$st" == "1" ]]; then
            [[ -n "$name" ]] && f_name="$name" || missing+=("name")
            [[ -n "$desc" ]] && f_desc="$desc" || missing+=("description")
            [[ -n "$runs" ]] && f_runs="$runs" || missing+=("runs_on")
            if (( mode_ok )); then f_mode="$mode_lc"; else missing+=("mode"); fi
            [[ -n "$args" ]] && f_args="$args"
            if [[ -n "$rt_lc" ]]; then
                if (( rt_ok )); then f_rt="$rt_lc"; else missing+=("runtime"); fi
            fi
            [[ -z "$cat" ]] && missing+=("category")
            if (( ${#missing[@]} )); then
                msg="partial header (missing or invalid: ${missing[*]}); defaults used"
            else
                msg="header complete"
            fi
        elif [[ "$st" == "2" ]]; then
            msg="orion:begin without orion:end; defaults used"
        else
            msg="no header; defaults used"
        fi
        [[ "$ctl" == "1" ]] && msg="$msg; reserved control character stripped from header"
        status="TEMP"; listed=1
        name="$f_name"; desc="$f_desc"; runs="$f_runs"; mode="$f_mode"; args="$f_args"; rt="$f_rt"
        cat="$TEMP_CATEGORY"
    else
        case "$st" in
            0) status="WARN"; msg="no orion header (skipped)";;
            2) status="ERROR"; msg="orion:begin without orion:end within first ${HEADER_SCAN_LINES} lines (skipped)";;
            *)
                local probs=()
                [[ "$ctl" == "1" ]] && probs+=("header contains reserved control character")
                [[ -z "$name" ]] && probs+=("missing name")
                [[ -z "$cat" ]] && probs+=("missing category")
                [[ -z "$runs" ]] && probs+=("missing runs_on")
                [[ -z "$desc" ]] && probs+=("missing description")
                if [[ -z "$mode" ]]; then
                    probs+=("missing mode")
                elif (( ! mode_ok )); then
                    probs+=("invalid mode '$mode' (use read-only or changes-state)")
                fi
                (( rt_ok )) || probs+=("invalid runtime '$rt' (use bash or python)")
                [[ "$(lower "$cat")" == "$(lower "$TEMP_CATEGORY")" ]] && probs+=("category '$TEMP_CATEGORY' is reserved")
                if (( ${#probs[@]} )); then
                    local pr
                    status="ERROR"; msg=""
                    for pr in "${probs[@]}"; do msg="${msg:+$msg; }$pr"; done
                    msg="$msg (skipped)"
                else
                    status="OK"; msg="$name [$cat]"; listed=1
                    mode="$mode_lc"
                    [[ -n "$rt_lc" ]] && rt="$rt_lc" || rt="$rt_default"
                fi
                ;;
        esac
    fi

    # Only matters for bash tools (executed via their shebang); python runs through the interpreter
    local eff_rt="$rt_default"
    (( listed )) && eff_rt="$rt"
    if (( crlf )) && [[ "$eff_rt" == "bash" ]]; then
        if [[ "$status" == "OK" ]]; then
            status="WARN"; msg="CRLF line endings (will fail to run)"
        else
            msg="$msg; CRLF line endings (will fail to run)"
        fi
    fi

    SC_FILE+=("$f"); SC_STATUS+=("$status"); SC_MSG+=("$msg"); SC_LISTED+=("$listed"); SC_TEMP+=("$is_temp")
    SC_NAME+=("$name"); SC_CAT+=("$cat"); SC_RUNS+=("$runs"); SC_MODE+=("$mode")
    SC_ARGS+=("$args"); SC_DESC+=("$desc"); SC_RUNTIME+=("$rt")
}

# Scan scripts/ (regular) then scripts/temp/ (Temporary). Read-only: never writes.
scan_scripts() {
    SC_FILE=(); SC_STATUS=(); SC_MSG=(); SC_LISTED=(); SC_TEMP=()
    SC_NAME=(); SC_CAT=(); SC_RUNS=(); SC_MODE=(); SC_ARGS=(); SC_DESC=(); SC_RUNTIME=()
    [[ -d "$SCRIPTS_DIR" ]] || return 1
    local tier dir f base
    for tier in 0 1; do
        dir="$SCRIPTS_DIR"
        (( tier )) && dir="$SCRIPTS_DIR/temp"
        # A symlinked scripts/ or scripts/temp/ is unsupported: list nothing from it
        if [[ -L "$dir" ]]; then
            SC_FILE+=("$dir"); SC_STATUS+=("WARN"); SC_MSG+=("$dir/ is a symlink: unsupported, nothing listed"); SC_LISTED+=(0); SC_TEMP+=("$tier")
            SC_NAME+=(""); SC_CAT+=(""); SC_RUNS+=(""); SC_MODE+=(""); SC_ARGS+=(""); SC_DESC+=(""); SC_RUNTIME+=("")
            (( tier == 0 )) && break
            continue
        fi
        for f in "$dir"/*; do
            [[ -e "$f" || -L "$f" ]] || continue
            base="${f##*/}"
            case "$base" in
                _*|.*) continue;;
                *.sh|*.py) ;;
                *) continue;;
            esac
            if [[ -L "$f" ]]; then
                SC_FILE+=("$f"); SC_STATUS+=("WARN"); SC_MSG+=("symlink ignored"); SC_LISTED+=(0); SC_TEMP+=("$tier")
                SC_NAME+=(""); SC_CAT+=(""); SC_RUNS+=(""); SC_MODE+=(""); SC_ARGS+=(""); SC_DESC+=(""); SC_RUNTIME+=("")
                continue
            fi
            [[ -f "$f" ]] || continue
            scan_one "$f" "$tier"
        done
    done
    merge_category_case
    return 0
}

# Sorted (case-insensitive by name, then original name, then index) list of
# listed-tool lines "lcname<US>name<US>idx". $1 = optional category filter.
sorted_tool_lines() {
    local filter="$1" i
    local lines=()
    for i in "${!SC_FILE[@]}"; do
        [[ "${SC_LISTED[$i]}" == "1" ]] || continue
        [[ -n "$filter" && "$filter" != "$ALL_FILTER" && "${SC_CAT[$i]}" != "$filter" ]] && continue
        lines+=("$(lower "${SC_NAME[$i]}")${US}${SC_NAME[$i]}${US}$(printf '%06d' "$i")")
    done
    (( ${#lines[@]} )) && printf '%s\n' "${lines[@]}" | LC_ALL=C sort
}

# Categories that differ only in case merge into one entry, spelled like the
# first such tool in sorted order; other spellings get a --check WARN.
merge_category_case() {
    local canon_lc=() canon_val=() canon_file=()
    local line idx lc k found
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        idx=$((10#${line##*"$US"}))
        [[ "${SC_TEMP[$idx]}" == "1" ]] && continue
        lc="$(lower "${SC_CAT[$idx]}")"
        found=-1
        for k in "${!canon_lc[@]}"; do
            [[ "${canon_lc[$k]}" == "$lc" ]] && { found=$k; break; }
        done
        if (( found < 0 )); then
            canon_lc+=("$lc"); canon_val+=("${SC_CAT[$idx]}"); canon_file+=("${SC_FILE[$idx]}")
        elif [[ "${SC_CAT[$idx]}" != "${canon_val[$found]}" ]]; then
            local own="${SC_CAT[$idx]}"
            SC_CAT[$idx]="${canon_val[$found]}"
            SC_MSG[$idx]="category spelling differs in case: $own vs ${canon_val[$found]} (see ${canon_file[$found]})"
            [[ "${SC_STATUS[$idx]}" == "OK" ]] && SC_STATUS[$idx]="WARN"
        fi
    done < <(sorted_tool_lines "")
}

# Split an argument line into PARSED_ARGS without eval, expansion or globbing.
# Whitespace separates words; '...' is literal; "..." groups (only \" and \\
# are escapes); a backslash outside quotes escapes the next character.
# Returns 1 (and sets PARSE_ARGS_ERR) on an unterminated quote or trailing "\".
PARSED_ARGS=(); PARSE_ARGS_ERR=""
parse_args() {
    local line="$1" i=0 n=${#1} c cur="" inword=0 q=""
    PARSED_ARGS=(); PARSE_ARGS_ERR=""
    while (( i < n )); do
        c="${line:i:1}"
        if [[ "$q" == "'" ]]; then
            if [[ "$c" == "'" ]]; then q=""; else cur+="$c"; fi
        elif [[ "$q" == '"' ]]; then
            if [[ "$c" == '"' ]]; then
                q=""
            elif [[ "$c" == '\' && ( "${line:i+1:1}" == '"' || "${line:i+1:1}" == '\' ) ]]; then
                cur+="${line:i+1:1}"; ((i++))
            else
                cur+="$c"
            fi
        else
            case "$c" in
                ' '|$'\t')
                    if (( inword )); then PARSED_ARGS+=("$cur"); cur=""; inword=0; fi;;
                "'") q="'"; inword=1;;
                '"') q='"'; inword=1;;
                '\')
                    if (( i + 1 >= n )); then PARSE_ARGS_ERR="trailing backslash"; PARSED_ARGS=(); return 1; fi
                    cur+="${line:i+1:1}"; inword=1; ((i++));;
                *) cur+="$c"; inword=1;;
            esac
        fi
        ((i++))
    done
    if [[ -n "$q" ]]; then PARSE_ARGS_ERR="unterminated $q quote"; PARSED_ARGS=(); return 1; fi
    (( inword )) && PARSED_ARGS+=("$cur")
    return 0
}

# Colored mode text for display
mode_display() {
    case "$1" in
        changes-state)  printf '%s' "${BOLD}${RED}changes-state (can modify the platform)${RESET}";;
        read-only)      printf '%s' "${GREEN}read-only${RESET}";;
        *)              printf '%s' "${YELLOW}${1}${RESET}";;
    esac
}

# --- UI ---------------------------------------------------------------------
draw_menu() {
    clear
    echo "${BOLD}${CYAN}=== ${APP_NAME} v${VERSION} ===${RESET}"
    echo

    if [[ "$MODE" == "tools" ]]; then
        if [[ "$SELECTED_CATEGORY" == "$ALL_FILTER" ]]; then
            echo "Category: All tools"
        else
            echo "Category: $SELECTED_CATEGORY"
        fi
        echo "Results: $VISIBLE_COUNT  Page: $((CURRENT_PAGE+1))/$((TOTAL_PAGES==0?1:TOTAL_PAGES))"
    elif [[ "$MODE" == "tool_detail" ]]; then
        local i="$SELECTED_IDX"
        echo "Tool: ${SC_NAME[$i]}"
        echo
        if [[ "${SC_TEMP[$i]}" == "1" ]]; then
            echo "${BOLD}${YELLOW}NOTICE: This is a TEMPORARY script. It has not been documented or reviewed for a release.${RESET}"
            echo
        fi
        echo "${BOLD}Description:${RESET} ${SC_DESC[$i]}"
        echo "Category: ${SC_CAT[$i]}"
        echo "Runs on: ${SC_RUNS[$i]}"
        echo "Mode: $(mode_display "${SC_MODE[$i]}")"
        [[ -n "${SC_ARGS[$i]}" ]] && echo "Args: ${SC_ARGS[$i]}"
        echo "Runtime: ${SC_RUNTIME[$i]}"
        echo "Source: local (${SC_FILE[$i]})"
        echo
    fi

    for i in "${!MENU_OPTIONS[@]}"; do
        if [[ $i -eq $CURSOR ]]; then
            echo "${YELLOW}> ${MENU_OPTIONS[$i]}${RESET}"
        else
            echo "  ${MENU_OPTIONS[$i]}"
        fi
    done

    echo
    case "$MODE" in
        "categories")
            echo "${CYAN}↑/↓: Move  Enter: Select  q: Quit${RESET}"
            ;;
        "tools")
            # n/p first, then search
            echo "${CYAN}↑/↓: Move  Enter: Select  b: Back  q: Quit  n/p: Next/Prev page  /: Search${RESET}"
            ;;
        "tool_detail")
            echo "${CYAN}↑/↓: Move  Enter: Select  b: Back  q: Quit${RESET}"
            ;;
    esac
}

# Load categories from the scanned catalog (alphabetical; Temporary always last)
load_categories() {
    MENU_OPTIONS=()
    MENU_ACTIONS=()

    local i have_temp=0
    local cats=()
    for i in "${!SC_FILE[@]}"; do
        [[ "${SC_LISTED[$i]}" == "1" ]] || continue
        if [[ "${SC_TEMP[$i]}" == "1" ]]; then
            have_temp=1
        else
            cats+=("$(lower "${SC_CAT[$i]}")${US}${SC_CAT[$i]}")
        fi
    done

    local cat
    if (( ${#cats[@]} )); then
        while IFS= read -r cat; do
            [[ -z "$cat" ]] && continue
            cat="${cat#*"$US"}"
            MENU_OPTIONS+=("$cat")
            MENU_ACTIONS+=("$cat")
        done < <(printf '%s\n' "${cats[@]}" | LC_ALL=C sort -u)
    fi
    if (( have_temp )); then
        MENU_OPTIONS+=("$TEMP_CATEGORY")
        MENU_ACTIONS+=("$TEMP_CATEGORY")
    fi

    MENU_OPTIONS+=("All tools")
    MENU_ACTIONS+=("$ALL_FILTER")
}

# Load tools for a selected category (alphabetically, with search filter, paginated)
load_tools() {
    local filter_category="$1"
    MENU_OPTIONS=()
    MENU_ACTIONS=()

    # Search in names and descriptions (case-insensitive); sort case-insensitively
    local sorted=() line idx name_lc desc_lc
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        idx=$((10#${line##*"$US"}))
        name_lc=$(lower "${SC_NAME[$idx]}")
        desc_lc=$(lower "${SC_DESC[$idx]}")
        if [[ -z "$SEARCH_TERM" || "$name_lc" == *"$SEARCH_TERM"* || "$desc_lc" == *"$SEARCH_TERM"* ]]; then
            sorted+=("$idx")
        fi
    done < <(sorted_tool_lines "$filter_category")

    # Pagination bookkeeping
    VISIBLE_COUNT="${#sorted[@]}"
    TOTAL_PAGES=$(( (VISIBLE_COUNT + PAGE_SIZE - 1) / PAGE_SIZE ))
    (( CURRENT_PAGE >= TOTAL_PAGES )) && CURRENT_PAGE=$(( TOTAL_PAGES>0 ? TOTAL_PAGES-1 : 0 ))
    local start=$(( CURRENT_PAGE * PAGE_SIZE ))
    local end=$(( start + PAGE_SIZE - 1 ))

    local label i
    for i in "${!sorted[@]}"; do
        (( i < start || i > end )) && continue
        idx="${sorted[$i]}"

        # Show description in list: "Name — Description" ([TEMP] prefix for temporary tier)
        label="${SC_NAME[$idx]} — ${SC_DESC[$idx]}"
        [[ "${SC_TEMP[$idx]}" == "1" ]] && label="[TEMP] $label"
        MENU_OPTIONS+=("$label")
        MENU_ACTIONS+=("tool:$idx")
    done

    # Pager controls (only when needed)
    if (( CURRENT_PAGE < TOTAL_PAGES-1 )); then
        MENU_OPTIONS+=("→ Next page")
        MENU_ACTIONS+=("next_page")
    fi
    if (( CURRENT_PAGE > 0 )); then
        MENU_OPTIONS+=("← Prev page")
        MENU_ACTIONS+=("prev_page")
    fi

    MENU_OPTIONS+=("Back to categories")
    MENU_ACTIONS+=("back_categories")
}

# Load tool detail menu (Run / Back)
load_tool_detail() {
    MENU_OPTIONS=("Run tool" "Back to tools")
    MENU_ACTIONS=("run" "back")
}

# Choose python interpreter (python3 preferred)
pick_python() {
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
    elif command -v python >/dev/null 2>&1; then
        echo "python"
    else
        echo ""
    fi
}

# Run a tool in place from scripts/
run_tool() {
    local idx="$1"
    shift
    local extra_args=("$@")
    local name="${SC_NAME[$idx]}" url="${SC_FILE[$idx]}" runtime="${SC_RUNTIME[$idx]}"

    if ! validate_local_source "$url"; then
        echo "${RED}Invalid local script path: $url${RESET}"
        read -rp "Press enter to continue..." || exit 0
        return
    fi
    local local_path="./${url#./}"
    if [[ ! -f "$local_path" || ! -s "$local_path" ]]; then
        echo "${RED}Local script missing or empty: $local_path${RESET}"
        read -rp "Press enter to continue..." || exit 0
        return
    fi
    echo "${GREEN}Running $name...${RESET}"
    if [[ "$runtime" == "python" ]]; then
        local py; py=$(pick_python)
        if [[ -z "$py" ]]; then
            echo "${RED}No python interpreter found (tried python3, python).${RESET}"
            read -rp "Press enter to continue..." || exit 0
            return
        fi
        "$py" "$local_path" "${extra_args[@]}"
    else
        chmod +x "$local_path"
        "$local_path" "${extra_args[@]}"
    fi
    local rc=$?
    if (( rc == 0 )); then
        echo "${GREEN}Tool execution finished.${RESET}"
    else
        echo "${RED}Tool exited with code $rc.${RESET}"
    fi
    read -rp "Press enter to continue..." || exit 0
}

# Main menu loop
menu_loop() {
    CURSOR=0
    MODE="categories"
    load_categories

    while true; do
        draw_menu
        read -rsn1 key || exit 0   # EOF on stdin: leave cleanly (never delete anything)
        case "$key" in
            $'\x1b')
                # Use portable tiny-timeout for escape sequence lookahead
                if read -rsn2 "${READ_TINY_TIMEOUT[@]}" rest; then
                    case "$rest" in
                        '[A') ((CURSOR--));;
                        '[B') ((CURSOR++));;
                    esac
                fi
                ((CURSOR<0)) && CURSOR=$((${#MENU_OPTIONS[@]}-1))
                ((CURSOR>=${#MENU_OPTIONS[@]})) && CURSOR=0
                ;;
            "") # Enter
                if [[ "$MODE" == "categories" ]]; then
                    SELECTED_CATEGORY="${MENU_ACTIONS[$CURSOR]}"
                    MODE="tools"
                    SEARCH_TERM=""
                    CURRENT_PAGE=0
                    load_tools "$SELECTED_CATEGORY"
                    CURSOR=0
                elif [[ "$MODE" == "tools" ]]; then
                    data="${MENU_ACTIONS[$CURSOR]}"
                    if [[ "$data" == "back_categories" ]]; then
                        MODE="categories"
                        load_categories
                        CURSOR=0
                    elif [[ "$data" == "next_page" ]]; then
                        ((CURRENT_PAGE++))
                        load_tools "$SELECTED_CATEGORY"
                        CURSOR=0
                    elif [[ "$data" == "prev_page" ]]; then
                        ((CURRENT_PAGE--))
                        load_tools "$SELECTED_CATEGORY"
                        CURSOR=0
                    else
                        SELECTED_IDX="${data#tool:}"
                        MODE="tool_detail"
                        load_tool_detail
                        CURSOR=0
                    fi
                elif [[ "$MODE" == "tool_detail" ]]; then
                    local action="${MENU_ACTIONS[$CURSOR]}"
                    if [[ "$action" == "run" ]]; then
                        local args_line prompt="Arguments (optional): "
                        [[ -n "${SC_ARGS[$SELECTED_IDX]}" ]] && prompt="Arguments (optional; expects: ${SC_ARGS[$SELECTED_IDX]}): "
                        read -rp "$prompt" args_line || exit 0
                        if ! parse_args "$args_line"; then
                            echo "${RED}Could not parse arguments: $PARSE_ARGS_ERR. Tool not run.${RESET}"
                            read -rp "Press enter to continue..." || exit 0
                            continue
                        fi
                        local args=("${PARSED_ARGS[@]}")
                        run_tool "$SELECTED_IDX" "${args[@]}"
                        load_tool_detail
                        CURSOR=0
                    elif [[ "$action" == "back" ]]; then
                        MODE="tools"
                        load_tools "$SELECTED_CATEGORY"
                        CURSOR=0
                    fi
                fi
                ;;
            "b"|"B")
                if [[ "$MODE" == "tools" ]]; then
                    MODE="categories"
                    load_categories
                    CURSOR=0
                elif [[ "$MODE" == "tool_detail" ]]; then
                    MODE="tools"
                    load_tools "$SELECTED_CATEGORY"
                    CURSOR=0
                fi
                ;;
            "q"|"Q")
                exit 0
                ;;
            "/")
                if [[ "$MODE" == "tools" ]]; then
                    read -rp "Search term (blank = reset): " SEARCH_TERM || exit 0
                    SEARCH_TERM=$(lower "$SEARCH_TERM")
                    CURRENT_PAGE=0
                    load_tools "$SELECTED_CATEGORY"
                    CURSOR=0
                fi
                ;;
            "n"|"N")
                if [[ "$MODE" == "tools" && $((CURRENT_PAGE+1)) -lt $TOTAL_PAGES ]]; then
                    ((CURRENT_PAGE++))
                    load_tools "$SELECTED_CATEGORY"
                    CURSOR=0
                fi
                ;;
            "p"|"P")
                if [[ "$MODE" == "tools" && $CURRENT_PAGE -gt 0 ]]; then
                    ((CURRENT_PAGE--))
                    load_tools "$SELECTED_CATEGORY"
                    CURSOR=0
                fi
                ;;
        esac
    done
}

# CLI helpers
print_version() {
    echo "${APP_NAME} ${VERSION}"
}

print_usage() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS]

Launch the ${APP_NAME} interactive menu for remote diagnostics.

The tool catalog is built from header comments in scripts/*.sh|*.py;
scripts/temp/ holds undocumented Temporary scripts.

Options:
  -h, --help      Show this help message and exit
  -V, --version   Show the ${APP_NAME} version and exit
      --check     Validate script headers (OK/WARN/ERROR/TEMP per file) and exit;
                  exit status is 0 only when every scanned file is OK
EOF
}

# Print per-file header status; exit status 1 unless every scanned file is OK
check_catalog() {
    if ! scan_scripts; then
        echo "${RED}Scripts directory not found: $SCRIPTS_DIR${RESET}" >&2
        return 1
    fi
    local i n_ok=0 n_warn=0 n_err=0 n_temp=0 color
    for i in "${!SC_FILE[@]}"; do
        case "${SC_STATUS[$i]}" in
            OK)    n_ok=$((n_ok+1)); color="$GREEN";;
            WARN)  n_warn=$((n_warn+1)); color="$YELLOW";;
            ERROR) n_err=$((n_err+1)); color="$RED";;
            TEMP)  n_temp=$((n_temp+1)); color="$YELLOW";;
        esac
        printf '%s%-5s%s %s: %s\n' "$color" "${SC_STATUS[$i]}" "$RESET" "${SC_FILE[$i]}" "${SC_MSG[$i]}"
        if [[ "${SC_STATUS[$i]}" == "TEMP" ]]; then
            printf '      reminder: promote it - add an orion header and move it out of %s/temp/\n' "$SCRIPTS_DIR"
        fi
    done
    echo
    local cats=() cat_line="(none)"
    load_categories
    for i in "${!MENU_ACTIONS[@]}"; do
        [[ "${MENU_ACTIONS[$i]}" == "$ALL_FILTER" ]] && continue
        cats+=("${MENU_OPTIONS[$i]}")
    done
    if (( ${#cats[@]} )); then
        cat_line=$(printf '%s, ' "${cats[@]}"); cat_line="${cat_line%, }"
    fi
    echo "Categories in use: $cat_line"
    echo "Summary: ${#SC_FILE[@]} file(s): $n_ok OK, $n_warn WARN, $n_err ERROR, $n_temp TEMP"
    (( n_warn + n_err + n_temp == 0 )) && return 0
    return 1
}

main() {
    local do_check=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_usage
                return 0
                ;;
            -V|--version)
                print_version
                return 0
                ;;
            --check)
                do_check=1
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "${RED}Unknown option: $1${RESET}" >&2
                print_usage >&2
                return 1
                ;;
            *)
                echo "${RED}Unexpected argument: $1${RESET}" >&2
                print_usage >&2
                return 1
                ;;
        esac
        shift
    done

    if (( do_check )); then
        check_catalog
        return $?
    fi

    if ! scan_scripts; then
        echo "${RED}Scripts directory not found: $SCRIPTS_DIR${RESET}" >&2
        return 1
    fi
    local listed=0 i
    for i in "${!SC_LISTED[@]}"; do [[ "${SC_LISTED[$i]}" == "1" ]] && listed=1; done
    if (( ! listed )); then
        if [[ -L "$SCRIPTS_DIR" ]]; then
            echo "${RED}$SCRIPTS_DIR is a symlink, which is unsupported: no tools listed (run with --check for details).${RESET}" >&2
        else
            echo "${RED}No tools found in $SCRIPTS_DIR (run with --check to see why).${RESET}" >&2
        fi
        return 1
    fi

    menu_loop
}

main "$@"
