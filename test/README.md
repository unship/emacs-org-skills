# claude-orgmode Tests

This directory contains [Buttercup](https://github.com/jorgenschaefer/emacs-buttercup)
tests for claude-orgmode.

The suite is **mocked**: it does not install or require a real note-taking
backend. The backend is forced to `vulpea` and the vulpea API is replaced with
an in-memory note store plus `fset` stubs (see `test-helper.el`). The mock's
`vulpea-create` writes real `.org` files into a per-test temporary directory, so
file-existence checks, content assertions, and the section-editing code (which
re-opens the file and navigates by `:ID:`) all run against real files without a
real vulpea/org-roam install.

## Test Structure

```
test/
├── README.md                            # This file
├── test-helper.el                       # Mocked vulpea harness + fixtures
├── claude-orgmode-test.el               # Unit tests
├── claude-orgmode-integration-test.el   # Integration workflows
└── claude-orgmode-plugin-test.el        # Plugin structure + full-API workflow
```

## Test Types

### Unit Tests (`claude-orgmode-test.el`)
Backend-agnostic helpers tested directly, plus backend dispatch tested against
the mocked vulpea API:
- Tag sanitization (`claude-orgmode--sanitize-tag`)
- Time-format expansion (`claude-orgmode--expand-time-formats`)
- Org-syntax validation (`claude-orgmode--validate-org-syntax`)
- Content-file reading (`claude-orgmode--read-content-file`)
- Temp-file detection (`claude-orgmode--looks-like-temp-file`)
- `claude-orgmode-create-note`: content, content-file priority, temp-file
  cleanup / `:keep-file`, and the tag-sanitization regression guard (verifies
  the sanitized tag is what reaches `vulpea-create`)
- Backend dispatch: each `claude-orgmode--backend-*` function is spied on and
  asserted to call the correct `vulpea-*` function with the correct arguments

### Integration Tests (`claude-orgmode-integration-test.el`)
Complete workflows against the in-memory store and real `.org` files:
- Note creation (basic, with content, tag sanitization)
- Search (by title, by tag, by node)
- Links (bidirectional, forward links, backlinks)
- Tag management (list, count, add, notes without tags)
- Utilities (orphan detection, recent notes, graph stats)
- Section editing (get / create / replace / append / delete) — each test writes
  a real `.org` file with known IDs and registers them via
  `claude-orgmode-test--register-note`
- Edge cases (empty store, nonexistent notes)

### Plugin Tests (`claude-orgmode-plugin-test.el`)
- Plugin structure: `marketplace.json` validity (merged
  `xenodium-emacs-skills` marketplace), org skill `SKILL.md` files, the eval
  script, and shared reference docs
- Package loading: all modules, public API functions, and backend dispatch
  functions are defined
- Full-API workflow against the mocked vulpea backend

## Running Tests

The project uses [Eldev](https://github.com/doublep/eldev). Mocked tests need no
backend package — Eldev only pulls in Buttercup.

**Install Eldev** (if not already on `PATH`):
```bash
curl -fsSL https://raw.githubusercontent.com/doublep/eldev/master/bin/eldev \
  -o "$HOME/.eldev/bin/eldev" && chmod +x "$HOME/.eldev/bin/eldev"
export PATH="$HOME/.eldev/bin:$PATH"
```

**Run tests:**
```bash
# Install test dependencies (first time only)
eldev -C --unstable prepare

# Run all tests
eldev -C --unstable test
```

If your Emacs build has a broken native compiler (e.g. `libgccjit` link
errors), disable native compilation for the run:
```bash
eldev -C --unstable \
  -S '(setq native-comp-jit-compilation nil native-comp-enable-subr-trampolines nil)' \
  test
```

Run a single file:
```bash
eldev -C --unstable test test/claude-orgmode-test.el
```

## Helper Functions

Available in `test-helper.el`:

- `claude-orgmode-test--setup` / `claude-orgmode-test--teardown` — install the
  mocks, create/destroy the temp note directory, set/reset
  `claude-orgmode--backend`
- `claude-orgmode-test--register-note (id path &optional level title tags)` —
  register a note in the mock store so backend lookups by ID resolve to a real
  `.org` file with the given `:level` (used by the section-editing tests)
- `claude-orgmode-test--count-nodes` — number of notes in the store
- `claude-orgmode-test--get-note-content` — read a note file's contents
- `claude-orgmode-test--node-exists-p` — whether a note with a title exists

The mock exposes the temp note directory as `claude-orgmode-test-directory`.

## Test Guidelines

1. Use descriptive `describe`/`it` names.
2. Test one behavior per spec.
3. Wrap stateful specs with `claude-orgmode-test--setup` /
   `claude-orgmode-test--teardown` (via `before-each` / `after-each`).
4. Assert behavior, not implementation: a mocked dispatch test must still
   assert the correct `vulpea-*` function was reached with the right arguments;
   backend-agnostic logic (sanitization, temp-file cleanup, section edits) is
   asserted on real inputs/outputs.

## Continuous Integration

For CI, Buttercup runs in batch mode via Eldev; no backend package is needed:

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        emacs_version: ['27.2', '28.2', '29.1']
    steps:
      - uses: actions/checkout@v4
      - uses: purcell/setup-emacs@master
        with:
          version: ${{ matrix.emacs_version }}
      - uses: actions/cache@v4
        with:
          path: ~/.eldev
          key: eldev-${{ matrix.emacs_version }}
      - name: Install Eldev
        run: curl -fsSL https://raw.github.com/doublep/eldev/master/webinstall/eldev | sh
      - name: Run tests
        run: eldev -C --unstable test
```

## Troubleshooting

### Native compiler errors (`libgccjit`, `ld: library not found`)

Some local Emacs builds ship a broken native compiler. Disable it for the run
with the `-S` flag shown under [Running Tests](#running-tests).

### Permission errors on temporary directories

The suite creates temp directories under the system temp directory. Ensure you
have write permission there.
