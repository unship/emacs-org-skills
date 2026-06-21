# CLAUDE.md

## What This Is

The org/vulpea note subsystem within the emacs-skills plugin. It contributes two skills:
1. **orgmode** - Pure org-mode syntax and formatting knowledge
2. **notes** - Note management via emacsclient, backed by vulpea

The elisp code and eval script are shared; the backend is vulpea.

## Architecture

**Plugin structure:**
- `.claude-plugin/marketplace.json` - Plugin metadata, references both skills
- `skills/orgmode/SKILL.md` - Knowledge-only skill (no tools)
- `skills/notes/SKILL.md` - Note management skill (create, edit, search, link)

**Shared code:**
- `elisp/claude-orgmode.el` - Main package loading all modules
- `elisp/claude-orgmode-backend.el` - Backend abstraction (vulpea-only)
- `elisp/claude-orgmode-*.el` - Modular implementations (core, create, section, search, links, tags, attach, utils, doctor)
- `scripts/claude-orgmode-eval` - Auto-load wrapper script

**Shared references:**
- `references/functions.md` - Complete function documentation
- `references/emacsclient-usage.md` - Emacsclient patterns
- `references/installation.md` - Setup and configuration guide
- `references/troubleshooting.md` - Common issues and solutions

**Skill-specific references:**
- `skills/orgmode/references/` - org-syntax.md, properties.md, timestamps.md, links.md, examples.md
- `skills/notes/references/vulpea-api.md` - Vulpea low-level API reference

## Auto-Load Architecture

**Wrapper script:** `scripts/claude-orgmode-eval`
- Checks if `claude-orgmode` is loaded in daemon
- Auto-loads from `elisp/` directory on first call
- Subsequent calls use already-loaded package (no overhead)
- Supports `-s`/`--socket` flag for multi-daemon setups (falls back to `EMACS_SOCKET_NAME` env var)

**Usage pattern:**
```bash
# Default (connects to "server" socket)
${CLAUDE_PLUGIN_ROOT}/scripts/claude-orgmode-eval "(claude-orgmode-create-note \"Title\")"

# Target a specific daemon
${CLAUDE_PLUGIN_ROOT}/scripts/claude-orgmode-eval -s myemacs "(claude-orgmode-create-note \"Title\")"
```

## Key Implementation Details

### Backend Abstraction

`elisp/claude-orgmode-backend.el` targets vulpea, the only supported backend:
1. Resolves vulpea lazily on first use (`require 'vulpea`), signalling an error if it is unavailable
2. Caches the result in the `claude-orgmode--backend` variable

All modules call `claude-orgmode--backend-*` helpers, which wrap the vulpea API in a stable interface.

### Note Creation

**`claude-orgmode-create-note`** delegates to `vulpea-create`, sanitizing tags
(hyphens become underscores) before creation.

**Implementation reference:** `elisp/claude-orgmode-create.el`

### Tag Sanitization

Org tags cannot contain hyphens. All tag functions automatically sanitize:
- `my-tag` → `my_tag`

**Implementation:** `elisp/claude-orgmode-tags.el`

### Attachments

Uses `org-attach` functions via the `claude-orgmode--with-node-context` helper.

**Implementation:** `elisp/claude-orgmode-attach.el`

### Formatting

All file-modifying operations auto-format using `claude-orgmode--format-buffer`.

**Implementation:** `elisp/claude-orgmode-core.el`

### Temp File Handling

- External `:content-file` parameters are automatically deleted after processing
- Only deletes files in temp directories (`/tmp/`, `/var/tmp/`, and `temporary-file-directory`)
- Use `:keep-file t` to prevent deletion

## Testing & Development

Uses [Buttercup](https://github.com/jorgenschaefer/emacs-buttercup) for testing and [Eldev](https://github.com/doublep/eldev) for test execution.

**IMPORTANT**: All new functions and significant code changes require tests.

### Quick Commands

```bash
eldev -C --unstable test     # Run all tests
eldev -C --unstable lint     # Run linting checks
eldev -C --unstable prepare  # Install dependencies
eldev -C --unstable clean    # Remove compiled files and cache
```

### Test Structure

**Test files:**
- `test/claude-orgmode-test.el` - Unit tests
- `test/claude-orgmode-integration-test.el` - Integration tests
- `test/test-helper.el` - Test helpers and utilities

### Pre-Commit Checklist

Before committing changes:
1. Run `eldev -C --unstable test` - all tests must pass
2. Run `eldev -C --unstable lint` - no linting errors
3. Add tests for new functionality
4. Update tests if changing existing behavior

