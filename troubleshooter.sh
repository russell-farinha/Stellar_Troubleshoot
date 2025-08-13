#!/usr/bin/env bash
#
# Photon Sensor Troubleshooter
# Modular, menu-driven tool for Stellar Cyber Photon sensors
# Ubuntu 22.x, dependency-free
#
# CONFIG FORMAT:
# CATEGORY|NAME|DESCRIPTION|URL
# Lines starting with '#' are ignored

CONFIG_FILE="./tools.conf"
BASE_DIR="./tools"

# Hardcoded category order
CATEGORIES=(
    "General Sensor Tools"
    "Connectors"
    "Parsers"
    "System Diagnostics"
)

# Colors
BOLD=$(tput bold)
RESET=$(tput sgr0)
CYAN=$(tput setaf 6)
YELLOW=$(tput setaf 3)
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)

tolower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

MODE="categories"   # "categories" or "tools"
SELECTED_CATEGORY=""
SEARCH_TERM=""

# Draw menu with instructions based on mode
draw_menu() {
    clear
    echo "${BOLD}${CYAN}=== Photon Sensor Troubleshooter ===${RESET}"
    echo "Use UP/DOWN arrows to navigate, ENTER to select"
    if [[ "$MODE" == "categories" ]]; then
        echo "Press 'q' to quit"
    else
        echo "Press '/' to search, 'b' to go back, 'q' to quit (cleanup happens on quit)"
    fi
    echo

    local i=0
    for option in "${MENU_OPTIONS[@]}"; do
        if [[ $i -eq $CURSOR ]]; then
            echo "${YELLOW}> $option${RESET}"
        else
            echo "  $option"
        fi
        ((i++))
    done
}

# Load categories into menu arrays
load_categories() {
    MENU_OPTIONS=()
    MENU_ACTIONS=()

    for cat in "${CATEGORIES[@]}"; do
        MENU_OPTIONS+=("$cat")
        MENU_ACTIONS+=("$cat")
    done
    MENU_OPTIONS+=("All tools")
    MENU_ACTIONS+=("all")
}

# Load tools filtered by category and search term
load_tools() {
    local filter_category="$1"
    MENU_OPTIONS=()
    MENU_ACTIONS=()

    while IFS='|' read -r category name description url; do
        [[ -z "$category" || "$category" == \#* ]] && continue

        local name_lc=$(tolower "$name")

        if [[ -z "$SEARCH_TERM" || "$name_lc" == *"$SEARCH_TERM"* ]]; then
            if [[ -z "$filter_category" || "$filter_category" == "all" || "$category" == "$filter_category" ]]; then
                MENU_OPTIONS+=("$category: $name - $description")
                MENU_ACTIONS+=("$category|$name|$url")
            fi
        fi
    done < "$CONFIG_FILE"
}

# Run selected tool
run_tool() {
    local category="$1"
    local name="$2"
    local url="$3"

    local dir="$BASE_DIR/$category"
    mkdir -p "$dir"

    local script_path="$dir/${name// /_}.sh"
    echo "${GREEN}Downloading tool...${RESET}"
    if ! curl -fsSL "$url" -o "$script_path"; then
        echo "${RED}Download failed!${RESET}"
        read -p "Press enter to continue..."
        return
    fi

    chmod +x "$script_path"
    echo "${GREEN}Running $name...${RESET}"
    "$script_path"

    echo "${GREEN}Tool execution finished.${RESET}"
    read -p "Press enter to continue..."
}

# Cleanup downloaded tools
cleanup_downloads() {
    echo "${YELLOW}Cleaning up all downloaded tool files...${RESET}"
    rm -rf "$BASE_DIR"/*
    echo "${YELLOW}Cleanup complete.${RESET}"
}

# Main menu loop handling categories/tools modes and input
menu_loop() {
    CURSOR=0
    while true; do
        draw_menu
        read -rsn1 key
        case "$key" in
            $'\x1b')
                if read -rsn2 -t 1 rest; then
                    case "$rest" in
                        '[A') ((CURSOR--));; # Up
                        '[B') ((CURSOR++));; # Down
                    esac
                fi
                ((CURSOR<0)) && CURSOR=$((${#MENU_OPTIONS[@]}-1))
                ((CURSOR>=${#MENU_OPTIONS[@]})) && CURSOR=0
                ;;
            "") # Enter key
                if [[ "$MODE" == "categories" ]]; then
                    SELECTED_CATEGORY="${MENU_ACTIONS[$CURSOR]}"
                    MODE="tools"
                    SEARCH_TERM=""
                    load_tools "$SELECTED_CATEGORY"
                    CURSOR=0
                else
                    IFS='|' read -r category name url <<< "${MENU_ACTIONS[$CURSOR]}"
                    run_tool "$category" "$name" "$url"
                    load_tools "$SELECTED_CATEGORY"
                    CURSOR=0
                fi
                ;;
            "b"|"B")
                if [[ "$MODE" == "tools" ]]; then
                    MODE="categories"
                    SEARCH_TERM=""
                    load_categories
                    CURSOR=0
                fi
                ;;
            "/") # Search only active in tools mode
                if [[ "$MODE" == "tools" ]]; then
                    echo
                    read -p "Search term: " term
                    SEARCH_TERM=$(tolower "$term")
                    load_tools "$SELECTED_CATEGORY"
                    CURSOR=0
                fi
                ;;
            "q"|"Q")
                cleanup_downloads
                clear
                exit 0
                ;;
        esac
    done
}

# Script start
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "${RED}Missing config file: $CONFIG_FILE${RESET}"
    exit 1
fi

MODE="categories"
load_categories
menu_loop
