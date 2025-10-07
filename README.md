# Project Orion

Project Orion is a simple, menu-driven runner for external scripts (for example
Gists or other raw URLs). The first time a tool is launched it is downloaded to
`./tools/`; subsequent runs reuse the cached copy unless you explicitly ask for
a fresh download.

## Files
- `troubleshooter.sh` — main runner that provides the interactive menu and CLI
  flags (`--help`, `--version`).
- `tools.conf` — configuration file listing tool metadata and source URLs.

## Usage

### Requirements
- `bash`
- `curl`
- Standard Unix text utilities: `awk`, `sed`, `sort`, `tr`

```bash
chmod +x troubleshooter.sh
./troubleshooter.sh
```

Running without arguments starts the interactive menu. Two CLI flags are
available for quick checks:

```bash
./troubleshooter.sh --help
./troubleshooter.sh --version
```

Both commands exit immediately after printing their respective information.

## Config format
Each non-comment line in `tools.conf` must contain four required columns
(`CATEGORY|NAME|DESCRIPTION|URL`) and may optionally supply a fifth column to
pin the runtime (`bash` or `python`):
```
CATEGORY|NAME|DESCRIPTION|URL[|RUNTIME]
```

If the runtime column is omitted, Project Orion infers it from the URL
extension (`.sh` → bash, `.py` → python). Any other extension defaults to bash
for backwards compatibility.

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
- Launch locally via `./troubleshooter.sh` to open the interactive menu.
- For CI/CD environments, point to the tagged release tarball or a commit hash to guarantee reproducibility.

## Content

- Tools defined in `tools.conf` appear in the interactive menu, grouped by category. You can filter them with `/` search, paginate with `n`/`p`, and view details before choosing to run.
- When launching a tool, Project Orion offers to reuse a cached download or to fetch a fresh copy. Downloads respect retry limits and configurable timeouts baked into `troubleshooter.sh`.
- Automated smoke tests cover key behaviours such as runtime detection, menu rendering under `clear` failures, pagination, search filtering, cached tool execution, and re-download requests. Run them locally before opening a pull request:

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
