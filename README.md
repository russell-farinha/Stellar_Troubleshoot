# Project Orion

Project Orion is a simple, menu-driven runner for external scripts (Gist/raw URLs).
This build **always re-downloads** the tool before execution (no cache prompt).

## Files
- `troubleshooter.sh` — main runner (interactive + `--run` CLI)
- `tools.conf` — 4 columns: `CATEGORY|NAME|DESCRIPTION|URL`

## Usage

### Requirements
- `bash`
- `curl`
- Standard Unix text utilities: `awk`, `sed`, `sort`, `tr`

```bash
chmod +x troubleshooter.sh
./troubleshooter.sh
```

### Run directly
```bash
./troubleshooter.sh --run --tool "Firewall Check" --category "System Diagnostics"
```

### Check version

```bash
./troubleshooter.sh --version
```

### Options
- `--config PATH`     Path to `tools.conf` (default: ./tools.conf)
- `--page-size N`     Items per page in menu (default: 8)
- `--run`             Non-interactive mode
- `--tool NAME`       Tool name (exact)
- `--category NAME`   Category filter for --run
- `--quiet`           Suppress non-essential output

## Config format
Each line:
```
CATEGORY|NAME|DESCRIPTION|URL
```

The runtime is inferred from the URL extension:
- `.sh` → runs with `bash`
- `.py` → runs with `python3` (falls back to `python`)

Keep your URLs **commit‑pinned** when possible to avoid unexpected changes.

## Versioning

Project Orion tracks its release number through the `SCRIPT_VERSION` constant near the top of `troubleshooter.sh`. To decide when and how to bump it:

1. **Group changes by user impact.** Bug fixes or documentation-only tweaks can share a patch release (e.g., `1.2.3 → 1.2.4`). Backwards-compatible feature work usually merits a minor bump (`1.2.3 → 1.3.0`), while breaking changes or large rewrites justify a major release (`1.2.3 → 2.0.0`).
2. **Update tests and docs in the same change.** The smoke test suite includes coverage for `--version`; refresh the expected value whenever you increment the constant, and mention notable changes in the README or changelog if present.
3. **Keep commits focused.** Each version bump should include only the modifications that correspond to the new release. Avoid mixing unrelated refactors with a version update so history stays easy to audit.
4. **Tag the release when merging.** After the pull request lands, create a git tag (e.g., `git tag v1.3.0 && git push origin v1.3.0`) so downstream users can pin to a specific revision.

If you're ever unsure which increment is appropriate, ask a maintainer for guidance and err on the side of smaller bumps—you can always ship another patch if needed.

## Release Cadence

Project Orion targets a monthly release cadence. Minor and patch releases can ship more frequently when urgent fixes are required, but every change must pass automated smoke tests before merging. Coordinate with maintainers to align feature work with the next planned release window.

## Security Review

All contributions undergo the standard pull-request review process, which includes checking for risky shell commands, ensuring downloaded scripts are commit-pinned, and verifying that secrets are never hard-coded. Significant changes to network access or execution permissions require a dedicated security sign-off prior to release.

## Engineering Release Process

1. Land feature or bug-fix pull requests with passing tests.
2. Prepare a release branch, update `SCRIPT_VERSION`, and refresh documentation as needed.
3. Run `./tests/run_tests.sh` and any additional environment-specific smoke checks.
4. Tag the release (e.g., `git tag vX.Y.Z`) and publish release notes that summarize key changes and known issues.
5. Notify stakeholders once the tag and notes are live.

## How-To Access

- Clone the repository: `git clone <repo-url>`.
- Ensure execution permissions: `chmod +x troubleshooter.sh`.
- Run locally via `./troubleshooter.sh` or specify `--run` options for scripted execution.
- For CI/CD environments, point to the tagged release tarball or a commit hash to guarantee reproducibility.

## Content

- The `debugging 123` tool can be run on the `xyz` environment by selecting it from the menu or invoking `./troubleshooter.sh --run --tool "debugging 123" --category "xyz"`.
- Automated smoke tests cover key behaviours such as runtime detection, menu rendering under `clear` failures, and cached tool execution when the tool itself exits non-zero. Run them locally before opening a pull request:

  ```bash
  ./tests/run_tests.sh
  ```

## Development & Testing

The script follows the standard “test first” loop:

1. Update or add tests that describe the behaviour you need.
2. Run `./tests/run_tests.sh` to watch them fail.
3. Implement the change in `troubleshooter.sh`.
4. Re-run the tests until they pass, then commit your work.

This repository uses a single main script, so the test harness loads it directly. Ensure any new helper functions are safe to source (i.e., keep interactive startup inside the `BASH_SOURCE` guard at the bottom of `troubleshooter.sh`).
