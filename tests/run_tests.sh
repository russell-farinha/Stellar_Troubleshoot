#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

# Load the troubleshooter functions without starting the interactive loop.
# shellcheck disable=SC1091
source "$ROOT_DIR/troubleshooter.sh"

tests_passed=0
tests_failed=0

fail() {
    local test_name="$1" message="$2"
    printf '❌ %s: %s\n' "$test_name" "$message"
    ((tests_failed++)) || true
}

pass() {
    local test_name="$1"
    printf '✅ %s\n' "$test_name"
    ((tests_passed++)) || true
}

assert_equals() {
    local expected="$1" actual="$2" name="$3"
    if [[ "$expected" != "$actual" ]]; then
        fail "$name" "expected '$expected' but got '$actual'"
        return 1
    fi
    return 0
}

run_test() {
    local test_name="$1"
    if "$test_name"; then
        pass "$test_name"
    else
        fail "$test_name" "unexpected failure"
    fi
}

reset_state() {
    MENU_OPTIONS=()
    MENU_ACTIONS=()
    CURSOR=0
    MODE="categories"
    SELECTED_CATEGORY=""
    SELECTED_TOOL_NAME=""
    SELECTED_TOOL_DESC=""
    SELECTED_TOOL_URL=""
    SELECTED_TOOL_RUNTIME=""
    SEARCH_TERM=""
    CURRENT_PAGE=0
    TOTAL_PAGES=0
    VISIBLE_COUNT=0
}

# --- Tests -----------------------------------------------------------------

test_detect_runtime_respects_explicit() {
    local result
    result=$(detect_runtime "https://example.com/script.sh" "Python")
    assert_equals "python" "$result" "test_detect_runtime_respects_explicit"
}

test_detect_runtime_inferrs_extension() {
    local result
    result=$(detect_runtime "https://example.com/tool.py" "")
    assert_equals "python" "$result" "test_detect_runtime_inferrs_extension"
}

test_draw_menu_survives_clear_failure() {
    reset_state
    MODE="categories"
    MENU_OPTIONS=("First" "Second")
    MENU_ACTIONS=("first" "second")
    CURSOR=0
    CURRENT_PAGE=0
    TOTAL_PAGES=1
    VISIBLE_COUNT=2
    SEARCH_TERM=""

    clear() { return 1; }

    if draw_menu >/dev/null; then
        unset -f clear
        return 0
    else
        unset -f clear
        return 1
    fi
}

test_run_tool_handles_failing_cached_script() {
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local original_base_dir="$BASE_DIR"
    BASE_DIR="$tmp_dir"
    local category="Diag"
    mkdir -p "$BASE_DIR/$category"
    local script_path="$BASE_DIR/$category/Test_Tool.sh"
    cat <<'SCRIPT' >"$script_path"
#!/usr/bin/env bash
exit 3
SCRIPT
    chmod +x "$script_path"

    local output rc=0
    output=$( { run_tool "$category" "Test Tool" "https://example.com/tool.sh" "bash"; } </dev/null 2>&1 ) || rc=$?

    BASE_DIR="$original_base_dir"
    rm -rf "$tmp_dir"

    if [[ $rc -ne 0 ]]; then
        printf '%s' "$output"
        return 1
    fi

    if [[ "$output" != *"Tool exited with code 3"* ]]; then
        printf '%s' "$output"
        return 1
    fi

    return 0
}

test_load_tools_handles_empty_search() {
    reset_state
    MODE="tools"
    SEARCH_TERM="nonexistent-term"
    CURRENT_PAGE=0
    CURSOR=0
    load_tools "all"

    if [[ ${#MENU_OPTIONS[@]} -eq 0 ]]; then
        printf 'menu options should always include navigation\n'
        return 1
    fi

    local last_index=$(( ${#MENU_ACTIONS[@]} - 1 ))
    if (( last_index < 0 )); then
        printf 'menu actions unexpectedly empty\n'
        return 1
    fi

    if [[ "${MENU_ACTIONS[$last_index]}" != "back_categories" ]]; then
        printf 'missing back navigation\n'
        return 1
    fi

    return 0
}

test_cli_version_flag() {
    local output
    if ! output=$("$ROOT_DIR/troubleshooter.sh" --version); then
        printf 'version command failed\n'
        return 1
    fi

    local expected="Stellar Troubleshoot $SCRIPT_VERSION"
    if [[ "$output" != "$expected" ]]; then
        printf 'expected "%s" but got "%s"\n' "$expected" "$output"
        return 1
    fi

    return 0
}

test_detect_runtime_defaults_to_bash() {
    local result
    result=$(detect_runtime "https://example.com/tool" "")
    assert_equals "bash" "$result" "test_detect_runtime_defaults_to_bash"
}

test_interpret_escape_sequence_handles_tmux_up_down() {
    local action
    action=$(interpret_escape_sequence "OA")
    assert_equals "up" "$action" "test_interpret_escape_sequence_handles_tmux_up"

    action=$(interpret_escape_sequence "OB")
    assert_equals "down" "$action" "test_interpret_escape_sequence_handles_tmux_down"

    action=$(interpret_escape_sequence "[1;5A")
    assert_equals "up" "$action" "test_interpret_escape_sequence_handles_csi_modifiers_up"

    action=$(interpret_escape_sequence "[1;5B")
    assert_equals "down" "$action" "test_interpret_escape_sequence_handles_csi_modifiers_down"
}

test_pick_python_prefers_python3() {
    local py
    py=$(pick_python)
    if [[ -z "$py" ]]; then
        printf 'pick_python did not find any interpreter\n'
        return 1
    fi

    if command -v python3 >/dev/null 2>&1 && [[ "$py" != "python3" ]]; then
        printf 'expected python3 but got %s\n' "$py"
        return 1
    fi

    return 0
}

test_load_categories_sorts_and_appends_all() {
    local tmp_conf
    tmp_conf=$(mktemp)
    cat <<'CONF' >"$tmp_conf"
Category B|Name 1|Desc|https://example.com/b.sh
Category A|Name 2|Desc|https://example.com/a.sh
Category B|Name 3|Desc|https://example.com/c.sh
# Comment line should be ignored
CONF

    local original_config="$CONFIG_FILE"
    CONFIG_FILE="$tmp_conf"

    reset_state
    load_categories

    local expected=("Category A" "Category B" "All tools")
    if [[ ${#MENU_OPTIONS[@]} -ne ${#expected[@]} ]]; then
        printf 'expected %d categories but found %d\n' "${#expected[@]}" "${#MENU_OPTIONS[@]}"
        rm -f "$tmp_conf"
        CONFIG_FILE="$original_config"
        return 1
    fi

    local i
    for i in "${!expected[@]}"; do
        if [[ "${MENU_OPTIONS[$i]}" != "${expected[$i]}" ]]; then
            printf 'expected "%s" at index %d but found "%s"\n' "${expected[$i]}" "$i" "${MENU_OPTIONS[$i]}"
            rm -f "$tmp_conf"
            CONFIG_FILE="$original_config"
            return 1
        fi
    done

    CONFIG_FILE="$original_config"
    rm -f "$tmp_conf"
    return 0
}

test_load_tools_paginates_results() {
    local tmp_conf
    tmp_conf=$(mktemp)
    cat <<'CONF' >"$tmp_conf"
Category|Alpha|First tool|https://example.com/a.sh
Category|Beta|Second tool|https://example.com/b.sh
Category|Gamma|Third tool|https://example.com/c.sh
Category|Delta|Fourth tool|https://example.com/d.sh
Category|Epsilon|Fifth tool|https://example.com/e.sh
CONF

    local original_config="$CONFIG_FILE"
    CONFIG_FILE="$tmp_conf"
    local original_page_size="$PAGE_SIZE"
    PAGE_SIZE=2

    reset_state
    MODE="tools"
    load_tools "Category"

    if [[ "$TOTAL_PAGES" -ne 3 ]]; then
        printf 'expected 3 total pages but found %d\n' "$TOTAL_PAGES"
        PAGE_SIZE="$original_page_size"
        CONFIG_FILE="$original_config"
        rm -f "$tmp_conf"
        return 1
    fi

    if [[ ${#MENU_OPTIONS[@]} -eq 0 ]]; then
        printf 'menu options unexpectedly empty\n'
        PAGE_SIZE="$original_page_size"
        CONFIG_FILE="$original_config"
        rm -f "$tmp_conf"
        return 1
    fi

    local last_index=$(( ${#MENU_OPTIONS[@]} - 1 ))
    if [[ "${MENU_OPTIONS[$last_index]}" != "Back to categories" ]]; then
        printf 'missing back to categories entry\n'
        PAGE_SIZE="$original_page_size"
        CONFIG_FILE="$original_config"
        rm -f "$tmp_conf"
        return 1
    fi

    local has_next=0 has_prev=0 option
    for option in "${MENU_OPTIONS[@]}"; do
        [[ "$option" == "→ Next page" ]] && has_next=1
        [[ "$option" == "← Prev page" ]] && has_prev=1
    done

    if (( has_next != 1 || has_prev != 0 )); then
        printf 'unexpected pagination state on first page (next=%d prev=%d)\n' "$has_next" "$has_prev"
        PAGE_SIZE="$original_page_size"
        CONFIG_FILE="$original_config"
        rm -f "$tmp_conf"
        return 1
    fi

    CURRENT_PAGE=2
    load_tools "Category"

    has_next=0
    has_prev=0
    for option in "${MENU_OPTIONS[@]}"; do
        [[ "$option" == "→ Next page" ]] && has_next=1
        [[ "$option" == "← Prev page" ]] && has_prev=1
    done

    if (( has_next != 0 || has_prev != 1 )); then
        printf 'unexpected pagination state on last page (next=%d prev=%d)\n' "$has_next" "$has_prev"
        PAGE_SIZE="$original_page_size"
        CONFIG_FILE="$original_config"
        rm -f "$tmp_conf"
        return 1
    fi

    PAGE_SIZE="$original_page_size"
    CONFIG_FILE="$original_config"
    rm -f "$tmp_conf"
    return 0
}

test_load_tools_search_filters_results() {
    local tmp_conf
    tmp_conf=$(mktemp)
    cat <<'CONF' >"$tmp_conf"
Category|Alpha|First tool|https://example.com/a.sh
Category|Beta|Second tool|https://example.com/b.sh
Category|Gamma|Special needle|https://example.com/c.sh
CONF

    local original_config="$CONFIG_FILE"
    CONFIG_FILE="$tmp_conf"

    reset_state
    MODE="tools"
    SEARCH_TERM="needle"
    load_tools "Category"

    if [[ "$VISIBLE_COUNT" -ne 1 ]]; then
        printf 'expected exactly one visible tool, found %d\n' "$VISIBLE_COUNT"
        CONFIG_FILE="$original_config"
        rm -f "$tmp_conf"
        return 1
    fi

    if [[ "${MENU_OPTIONS[0]}" != "Gamma — Special needle" ]]; then
        printf 'search results did not include expected tool (got "%s")\n' "${MENU_OPTIONS[0]}"
        CONFIG_FILE="$original_config"
        rm -f "$tmp_conf"
        return 1
    fi

    if [[ ${#MENU_OPTIONS[@]} -eq 0 ]]; then
        printf 'search returned an empty menu\n'
        CONFIG_FILE="$original_config"
        rm -f "$tmp_conf"
        return 1
    fi

    local last_index=$(( ${#MENU_OPTIONS[@]} - 1 ))
    if [[ "${MENU_OPTIONS[$last_index]}" != "Back to categories" ]]; then
        printf 'missing back navigation for search results\n'
        CONFIG_FILE="$original_config"
        rm -f "$tmp_conf"
        return 1
    fi

    CONFIG_FILE="$original_config"
    rm -f "$tmp_conf"
    return 0
}

test_draw_menu_includes_version_and_context() {
    reset_state
    MODE="tools"
    SELECTED_CATEGORY="Networking"
    VISIBLE_COUNT=3
    TOTAL_PAGES=2
    MENU_OPTIONS=("First" "Second")
    MENU_ACTIONS=("first" "second")
    CURSOR=0

    local original_clear=$(declare -f clear 2>/dev/null || true)
    clear() { return 0; }

    local original_colors=("$BOLD" "$RESET" "$CYAN" "$YELLOW")
    BOLD=""; RESET=""; CYAN=""; YELLOW=""

    local output
    output=$(draw_menu)

    local expected_header="=== Stellar Troubleshoot v$SCRIPT_VERSION ==="
    if [[ "$output" != *"$expected_header"* ]]; then
        printf 'menu header missing version (output: %s)\n' "$output"
        [[ -n "$original_clear" ]] && eval "$original_clear" || unset -f clear
        BOLD="${original_colors[0]}"; RESET="${original_colors[1]}"; CYAN="${original_colors[2]}"; YELLOW="${original_colors[3]}"
        return 1
    fi

    if [[ "$output" != *"Category: Networking"* ]]; then
        printf 'menu missing category context\n'
        [[ -n "$original_clear" ]] && eval "$original_clear" || unset -f clear
        BOLD="${original_colors[0]}"; RESET="${original_colors[1]}"; CYAN="${original_colors[2]}"; YELLOW="${original_colors[3]}"
        return 1
    fi

    [[ -n "$original_clear" ]] && eval "$original_clear" || unset -f clear
    BOLD="${original_colors[0]}"; RESET="${original_colors[1]}"; CYAN="${original_colors[2]}"; YELLOW="${original_colors[3]}"
    return 0
}

test_run_tool_uses_cached_copy_by_default() {
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local original_base_dir="$BASE_DIR"
    BASE_DIR="$tmp_dir"

    local category="Diag"
    mkdir -p "$BASE_DIR/$category"
    local script_path="$BASE_DIR/$category/Test_Tool.sh"
    cat <<'SCRIPT' >"$script_path"
#!/usr/bin/env bash
echo "cached run"
SCRIPT
    chmod +x "$script_path"

    local colors=("$GREEN" "$RESET")
    GREEN=""; RESET=""

    local output
    output=$(printf '\n\n' | run_tool "$category" "Test Tool" "https://example.com/tool.sh" "bash")

    BASE_DIR="$original_base_dir"
    GREEN="${colors[0]}"; RESET="${colors[1]}"
    rm -rf "$tmp_dir"

    if [[ "$output" != *"Running cached Test Tool..."* ]]; then
        printf 'expected cached execution path but output was: %s\n' "$output"
        return 1
    fi

    if [[ "$output" != *"Tool execution finished."* ]]; then
        printf 'expected success message but output was: %s\n' "$output"
        return 1
    fi

    return 0
}

test_run_tool_re_downloads_on_request() {
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local original_base_dir="$BASE_DIR"
    BASE_DIR="$tmp_dir"

    local category="Diag"
    mkdir -p "$BASE_DIR/$category"
    local script_path="$BASE_DIR/$category/Test_Tool.sh"
    echo '#!/usr/bin/env bash' >"$script_path"
    chmod +x "$script_path"

    local colors=("$GREEN" "$RESET")
    GREEN=""; RESET=""

    local marker
    marker=$(mktemp)
    local original_curl=$(declare -f curl 2>/dev/null || true)
    curl() {
        local out_path=""
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
                -o)
                    out_path="$2"
                    shift 2
                    ;;
                *)
                    shift
                    ;;
            esac
        done
        printf 'called' >"$marker"
        cat <<'SCRIPT' >"$out_path"
#!/usr/bin/env bash
exit 0
SCRIPT
        return 0
    }

    local output
    output=$(printf 'r\n\n' | run_tool "$category" "Test Tool" "https://example.com/tool.sh" "bash")

    [[ -n "$original_curl" ]] && eval "$original_curl" || unset -f curl
    BASE_DIR="$original_base_dir"
    GREEN="${colors[0]}"; RESET="${colors[1]}"

    local curl_called=0
    [[ -f "$marker" ]] && curl_called=1
    rm -f "$marker"
    rm -rf "$tmp_dir"

    if (( curl_called == 0 )); then
        printf 'expected curl to be invoked for re-download\n'
        return 1
    fi

    if [[ "$output" != *"Downloading tool..."* ]]; then
        printf 'expected download message but output was: %s\n' "$output"
        return 1
    fi

    return 0
}

test_run_tool_reports_missing_python() {
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local original_base_dir="$BASE_DIR"
    BASE_DIR="$tmp_dir"

    local category="Diag"
    mkdir -p "$BASE_DIR/$category"
    local script_path="$BASE_DIR/$category/Test_Tool.py"
    cat <<'SCRIPT' >"$script_path"
#!/usr/bin/env python3
print("hello")
SCRIPT
    chmod +x "$script_path"

    local colors=("$RED" "$RESET")
    RED=""; RESET=""

    local original_pick_python=$(declare -f pick_python)
    pick_python() { echo ""; }

    local output
    output=$(printf '\n' | run_tool "$category" "Test Tool" "https://example.com/tool.py" "python")

    eval "$original_pick_python"
    BASE_DIR="$original_base_dir"
    RED="${colors[0]}"; RESET="${colors[1]}"
    rm -rf "$tmp_dir"

    if [[ "$output" != *"No python interpreter found"* ]]; then
        printf 'expected missing python warning but got: %s\n' "$output"
        return 1
    fi

    return 0
}

test_cli_help_flag() {
    local output
    if ! output=$("$ROOT_DIR/troubleshooter.sh" --help); then
        printf 'help command failed\n'
        return 1
    fi

    if [[ "$output" != *"Usage: troubleshooter.sh"* ]]; then
        printf 'help output missing usage line\n'
        return 1
    fi

    if [[ "$output" != *"-V, --version"* ]]; then
        printf 'help output missing version flag documentation\n'
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------

main() {
    local tests=(
        test_detect_runtime_respects_explicit
        test_detect_runtime_inferrs_extension
        test_detect_runtime_defaults_to_bash
        test_interpret_escape_sequence_handles_tmux_up_down
        test_pick_python_prefers_python3
        test_load_categories_sorts_and_appends_all
        test_draw_menu_survives_clear_failure
        test_draw_menu_includes_version_and_context
        test_load_tools_handles_empty_search
        test_load_tools_paginates_results
        test_load_tools_search_filters_results
        test_run_tool_handles_failing_cached_script
        test_run_tool_uses_cached_copy_by_default
        test_run_tool_re_downloads_on_request
        test_run_tool_reports_missing_python
        test_cli_version_flag
        test_cli_help_flag
    )

    local test
    for test in "${tests[@]}"; do
        run_test "$test"
    done

    printf '\nTotals: %d passed, %d failed\n' "$tests_passed" "$tests_failed"
    if (( tests_failed > 0 )); then
        exit 1
    fi
}

main "$@"
