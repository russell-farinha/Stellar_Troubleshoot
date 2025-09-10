#!/usr/bin/env bash
#
# Stellar Troubleshoot
# Modular, menu-driven tool for Stellar Cyber services
# Ubuntu/Photon, dependency-free (bash + curl; optional python)
#

CONFIG_FILE="./tools.conf"
BASE_DIR="./tools"

# Hardcoded settings (no ENV needed)
PAGE_SIZE=5                  # Tools per page
CONNECT_TIMEOUT=5            # curl connect timeout (seconds)
MAX_TIME=60                  # curl max time (seconds)
DOWNLOAD_RETRIES=3           # curl retries on transient failures

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
SELECTED_TOOL_NAME=""
SELECTED_TOOL_DESC=""
SELECTED_TOOL_URL=""
SELECTED_TOOL_RUNTIME=""  # "bash" | "python"
SEARCH_TERM=""
CURRENT_PAGE=0
TOTAL_PAGES=0
VISIBLE_COUNT=0

# Ctrl-C exits cleanly with cleanup
trap 'echo; echo "${YELLOW}Exiting (Ctrl-C)...${RESET}"; rm -rf -- "$BASE_DIR"/* 2>/dev/null || true; clear; exit 130' INT

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

# --- Runtime detection -------------------------------------------------------
# Priority:
# 1) If a 5th column is present and equals "python" or "bash", use it.
# 2) Else infer from URL extension: .py => python, .sh => bash
# 3) Else default to bash (backward compatible)
detect_runtime() {
    local url="$1" explicit="$2"
    case "$(lower "$explicit")" in
        python|bash) echo "$(lower "$explicit")"; return;;
    esac
    local ext="${url##*.}"
    case "$(lower "$ext")" in
        py) echo "python";;
        sh) echo "bash";;
        *)  echo "bash";;
    esac
}

# --- UI ---------------------------------------------------------------------
draw_menu() {
    clear
    echo "${BOLD}${CYAN}=== Stellar Troubleshoot ===${RESET}"
    echo

    if [[ "$MODE" == "tools" ]]; then
        echo "Category: $SELECTED_CATEGORY"
        echo "Results: $VISIBLE_COUNT  Page: $((CURRENT_PAGE+1))/$((TOTAL_PAGES==0?1:TOTAL_PAGES))"
    elif [[ "$MODE" == "tool_detail" ]]; then
        echo "Tool: $SELECTED_TOOL_NAME"
        echo
        echo "${BOLD}Description:${RESET} $SELECTED_TOOL_DESC"
        echo "Runtime: ${SELECTED_TOOL_RUNTIME}"
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
            echo "${CYAN}↑/↓: Move  Enter: Select  q: Quit  r: Cleanup+Quit${RESET}"
            ;;
        "tools")
            # n/p first, then search
            echo "${CYAN}↑/↓: Move  Enter: Select  b: Back  q: Quit  r: Cleanup+Quit  n/p: Next/Prev page  /: Search${RESET}"
            ;;
        "tool_detail")
            echo "${CYAN}↑/↓: Move  Enter: Select  b: Back  q: Quit  r: Cleanup+Quit${RESET}"
            ;;
    esac
}

# Load categories dynamically (multi-word safe)
load_categories() {
    MENU_OPTIONS=()
    MENU_ACTIONS=()

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "${RED}Missing config file: $CONFIG_FILE${RESET}"
        exit 1
    fi

    CATEGORIES_TEMP=$(awk -F'|' '{gsub(/\r/,""); gsub(/^[ \t]+|[ \t]+$/,"",$1); if($1 != "" && $1 !~ /^#/) print $1}' "$CONFIG_FILE" | LC_ALL=C sort -u)

    while IFS= read -r cat; do
        [[ -z "$cat" ]] && continue
        MENU_OPTIONS+=("$cat")
        MENU_ACTIONS+=("$cat")
    done <<< "$CATEGORIES_TEMP"

    MENU_OPTIONS+=("All tools")
    MENU_ACTIONS+=("all")
}

# Load tools for a selected category (alphabetically, with search filter, paginated)
load_tools() {
    local filter_category="$1"
    MENU_OPTIONS=()
    MENU_ACTIONS=()

    # Temporary array to hold "name|category|name|description|url|runtime" for sorting
    local tmp_list=()

    while IFS='|' read -r category name description url runtime_col rest; do
        [[ -z "$category" || "$category" == \#* ]] && continue
        category=$(echo "$category" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')
        name=$(echo "$name" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')
        description=$(echo "$description" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')
        url=$(echo "$url" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')
        local runtime; runtime=$(detect_runtime "$url" "$runtime_col")

        if [[ "$filter_category" == "all" || "$category" == "$filter_category" ]]; then
            # Search in names and descriptions (case-insensitive)
            local name_lc desc_lc
            name_lc=$(lower "$name")
            desc_lc=$(lower "$description")
            if [[ -z "$SEARCH_TERM" || "$name_lc" == *"$SEARCH_TERM"* || "$desc_lc" == *"$SEARCH_TERM"* ]]; then
                tmp_list+=("$name|$category|$name|$description|$url|$runtime")
            fi
        fi
    done < "$CONFIG_FILE"

    # Sort alphabetically by tool name (locale-stable)
    IFS=$'\n' read -r -d '' -a sorted < <(printf '%s\n' "${tmp_list[@]}" | LC_ALL=C sort && printf '\0')
    unset IFS

    # Pagination bookkeeping
    VISIBLE_COUNT="${#sorted[@]}"
    TOTAL_PAGES=$(( (VISIBLE_COUNT + PAGE_SIZE - 1) / PAGE_SIZE ))
    (( CURRENT_PAGE >= TOTAL_PAGES )) && CURRENT_PAGE=$(( TOTAL_PAGES>0 ? TOTAL_PAGES-1 : 0 ))
    local start=$(( CURRENT_PAGE * PAGE_SIZE ))
    local end=$(( start + PAGE_SIZE - 1 ))

    for i in "${!sorted[@]}"; do
        (( i < start || i > end )) && continue
        IFS='|' read -r _ category name description url runtime <<< "${sorted[$i]}"

        # Show description in list: "Name — Description"
        local label="$name — $description"
        MENU_OPTIONS+=("$label")
        MENU_ACTIONS+=("$category|$name|$description|$url|$runtime")
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
    MENU_ACTIONS=("run|$SELECTED_CATEGORY|$SELECTED_TOOL_NAME|$SELECTED_TOOL_DESC|$SELECTED_TOOL_URL|$SELECTED_TOOL_RUNTIME" "back")
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

# Run a tool (with simple cache reuse + curl retries)
run_tool() {
    local category="$1"
    local name="$2"
    local url="$3"
    local runtime="$4"

    local dir="$BASE_DIR/$category"
    mkdir -p "$dir"

    # Pick a sensible file extension for caching
    local ext="sh"
    [[ "$runtime" == "python" ]] && ext="py"
    case "$(lower "${url##*.}")" in
        py) ext="py" ;;
        sh) ext="sh" ;;
    esac

    local script_path="$dir/${name// /_}.$ext"

    if [[ -f "$script_path" && -s "$script_path" ]]; then
        read -rp "Cached copy found. Use cached (u) or re-download (r)? [u/r]: " _ans
        if [[ "$(lower "${_ans:-u}")" != "r" ]]; then
            echo "${GREEN}Running cached $name...${RESET}"
            if [[ "$runtime" == "python" ]]; then
                local py; py=$(pick_python)
                if [[ -z "$py" ]]; then
                    echo "${RED}No python interpreter found (tried python3, python).${RESET}"
                    read -rp "Press enter to continue..."
                    return
                fi
                "$py" "$script_path"
            else
                chmod +x "$script_path"
                "$script_path"
            fi
            local rc=$?
            if (( rc == 0 )); then
                echo "${GREEN}Tool execution finished.${RESET}"
            else
                echo "${RED}Tool exited with code $rc.${RESET}"
            fi
            read -rp "Press enter to continue..."
            return
        fi
    fi

    echo "${GREEN}Downloading tool...${RESET}"
    if ! curl -fsSL --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
         --retry "$DOWNLOAD_RETRIES" --retry-delay 1 \
         -o "$script_path" "$url"; then
        echo "${RED}Download failed!${RESET}"
        read -rp "Press enter to continue..."
        return
    fi

    echo "${GREEN}Running $name...${RESET}"
    if [[ "$runtime" == "python" ]]; then
        local py; py=$(pick_python)
        if [[ -z "$py" ]]; then
            echo "${RED}No python interpreter found (tried python3, python).${RESET}"
            read -rp "Press enter to continue..."
            return
        fi
        "$py" "$script_path"
    else
        chmod +x "$script_path"
        "$script_path"
    fi

    local rc=$?
    if (( rc == 0 )); then
        echo "${GREEN}Tool execution finished.${RESET}"
    else
        echo "${RED}Tool exited with code $rc.${RESET}"
    fi
    read -rp "Press enter to continue..."
}

# Main menu loop
menu_loop() {
    CURSOR=0
    MODE="categories"
    load_categories

    while true; do
        draw_menu
        read -rsn1 key
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
                        IFS='|' read -r category name description url runtime <<< "${MENU_ACTIONS[$CURSOR]}"
                        SELECTED_CATEGORY="$category"
                        SELECTED_TOOL_NAME="$name"
                        SELECTED_TOOL_DESC="$description"
                        SELECTED_TOOL_URL="$url"
                        SELECTED_TOOL_RUNTIME="$runtime"
                        MODE="tool_detail"
                        load_tool_detail
                        CURSOR=0
                    fi
                elif [[ "$MODE" == "tool_detail" ]]; then
                    IFS='|' read -r action category name description url runtime <<< "${MENU_ACTIONS[$CURSOR]}"
                    if [[ "$action" == "run" ]]; then
                        run_tool "$category" "$name" "$url" "$runtime"
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
                # Quit WITHOUT cleanup
                exit 0
                ;;
            "r"|"R")
                # Cleanup and quit
                rm -rf -- "$BASE_DIR"/* 2>/dev/null || true
                clear
                exit 0
                ;;
            "/")
                if [[ "$MODE" == "tools" ]]; then
                    read -rp "Search term (blank = reset): " SEARCH_TERM
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

# Start
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "${RED}Missing config file: $CONFIG_FILE${RESET}"
    exit 1
fi

menu_loop
