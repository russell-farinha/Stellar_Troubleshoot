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
    local name="$1" message="$2"
    printf '❌ %s: %s\n' "$name" "$message"
    ((tests_failed++)) || true
}

pass() {
    local name="$1"
    printf '✅ %s\n' "$name"
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
    local name="$1"
    if "$name"; then
        pass "$name"
    else
        fail "$name" "unexpected failure"
    fi
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

# ---------------------------------------------------------------------------

main() {
    local test
    for test in \
        test_detect_runtime_respects_explicit \
        test_detect_runtime_inferrs_extension \
        test_draw_menu_survives_clear_failure \
        test_run_tool_handles_failing_cached_script
    do
        run_test "$test"
    done

    printf '\nTotals: %d passed, %d failed\n' "$tests_passed" "$tests_failed"
    if (( tests_failed > 0 )); then
        exit 1
    fi
}

main "$@"
