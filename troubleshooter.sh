#!/usr/bin/env bash
#
# Stellar Troubleshoot
# Modular, menu-driven tool for Stellar Cyber services
# Ubuntu 22.x, dependency-free
#

CONFIG_FILE="./tools.conf"
BASE_DIR="./tools"

# Colors
BOLD=$(tput bold)
RESET=$(tput sgr0)
CYAN=$(tput setaf 6)
YELLOW=$(tput setaf 3)
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)

# Globals
MENU_OPTIONS=()
MENU_ACTIONS=()
CURSOR=0
MODE="categories"  # categories | tools | tool_detail
SELECTED_CATEGORY=""
SELECTED_TOOL_NAME=""
SELECTED_TOOL_DESC=""
SELECTED_TOOL_URL=""
SEARCH_TERM=""

# Draw menu with dynamic guide
draw_menu() {
    clear
    echo "${BOLD}${CYAN}=== Stellar Troubleshoot ===${RESET}"
    echo

    if [[ "$MODE" == "tools" ]]; then
        echo "Category: $SELECTED_CATEGORY"
    elif [[ "$MODE" == "tool_detail" ]]; then
        echo "Tool: $SELECTED_TOOL_NAME"
        echo
        echo "${BOLD}Description:${RESET} $SELECTED_TOOL_DESC"
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
    # Dynamic guide based on mode
    case "$MODE" in
        "categories")
            echo "${CYAN}↑/↓: Move  Enter: Select  q: Quit${RESET}"
            ;;
        "tools")
            echo "${CYAN}↑/↓: Move  Enter: Select  b: Back  q: Quit  /: Search${RESET}"
            ;;
        "tool_detail")
            echo "${CYAN}↑/↓: Move  Enter: Select  b: Back  q: Quit${RESET}"
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

    CATEGORIES_TEMP=$(awk -F'|' '{gsub(/\r/,""); gsub(/^[ \t]+|[ \t]+$/,"",$1); if($1 != "" && $1 !~ /^#/) print $1}' "$CONFIG_FILE" | sort -u)

    while IFS= read -r cat; do
        MENU_OPTIONS+=("$cat")
        MENU_ACTIONS+=("$cat")
    done <<< "$CATEGORIES_TEMP"

    MENU_OPTIONS+=("All tools")
    MENU_ACTIONS+=("all")
}

# Load tools for a selected category (alphabetically, with search filter)
load_tools() {
    local filter_category="$1"
    MENU_OPTIONS=()
    MENU_ACTIONS=()

    # Temporary array to hold "name|full_data" for sorting
    local tmp_list=()

    while IFS='|' read -r category name description url; do
        [[ -z "$category" || "$category" == \#* ]] && continue
        category=$(echo "$category" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')
        name=$(echo "$name" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')
        description=$(echo "$description" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')
        url=$(echo "$url" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')

        if [[ "$filter_category" == "all" || "$category" == "$filter_category" ]]; then
            local name_lc=$(echo "$name" | tr '[:upper:]' '[:lower:]')
            if [[ -z "$SEARCH_TERM" || "$name_lc" == *"$SEARCH_TERM"* ]]; then
                tmp_list+=("$name|$category|$name|$description|$url")
            fi
        fi
    done < "$CONFIG_FILE"

    # Sort alphabetically by tool name
    IFS=$'\n' sorted=($(sort <<<"${tmp_list[*]}"))
    unset IFS

    for entry in "${sorted[@]}"; do
        IFS='|' read -r _ category name description url <<< "$entry"
        MENU_OPTIONS+=("$name")
        MENU_ACTIONS+=("$category|$name|$description|$url")
    done

    MENU_OPTIONS+=("Back to categories")
    MENU_ACTIONS+=("back_categories")
}

# Load tool detail menu (Run / Back)
load_tool_detail() {
    MENU_OPTIONS=("Run tool" "Back to tools")
    MENU_ACTIONS=("run|$SELECTED_CATEGORY|$SELECTED_TOOL_NAME|$SELECTED_TOOL_DESC|$SELECTED_TOOL_URL" "back")
}

# Run a tool
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
                if read -rsn2 -t 1 rest; then
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
                    load_tools "$SELECTED_CATEGORY"
                    CURSOR=0
                elif [[ "$MODE" == "tools" ]]; then
                    IFS='|' read -r data <<< "${MENU_ACTIONS[$CURSOR]}"
                    if [[ "$data" == "back_categories" ]]; then
                        MODE="categories"
                        load_categories
                        CURSOR=0
                    else
                        IFS='|' read -r category name description url <<< "${MENU_ACTIONS[$CURSOR]}"
                        SELECTED_CATEGORY="$category"
                        SELECTED_TOOL_NAME="$name"
                        SELECTED_TOOL_DESC="$description"
                        SELECTED_TOOL_URL="$url"
                        MODE="tool_detail"
                        load_tool_detail
                        CURSOR=0
                    fi
                elif [[ "$MODE" == "tool_detail" ]]; then
                    IFS='|' read -r action category name description url <<< "${MENU_ACTIONS[$CURSOR]}"
                    if [[ "$action" == "run" ]]; then
                        run_tool "$category" "$name" "$url"
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
                echo "${YELLOW}Exiting and cleaning up...${RESET}"
                rm -rf "$BASE_DIR"/*
                clear
                exit 0
                ;;
            "/")
                if [[ "$MODE" == "tools" ]]; then
                    read -p "Search term: " SEARCH_TERM
                    SEARCH_TERM=$(echo "$SEARCH_TERM" | tr '[:upper:]' '[:lower:]')
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
