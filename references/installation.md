# Installation and Setup

Simple installation guide for claude-orgmode.

## Prerequisites

You need:
1. **Emacs with vulpea installed and configured** (org-roam loads as vulpea's transitive dependency)
2. **Emacs daemon running**: `emacs --daemon` or `emacs --fg-daemon=<name>`
3. **Notes directory set up**: Your notes directory configured via `org-directory` (e.g., `~/Documents/org/`)
4. **vulpea database initialized**

That's it! No manual package loading or configuration needed.

## How Auto-Loading Works

The skill includes a wrapper script at `scripts/claude-orgmode-eval` that:
1. Checks if `claude-orgmode` package is loaded
2. If not, automatically loads it from the skill directory
3. Executes your elisp expression
4. On subsequent calls, package is already in memory (fast!)

You don't need to modify your Emacs configuration at all.

## Verification

### Check Emacs daemon is running

```bash
emacsclient --eval "t"
```

Should return `t`. If not, start the daemon:
```bash
emacs --daemon
```

For named daemons, specify the socket:
```bash
emacsclient --socket-name myemacs --eval "t"
```

### Check vulpea is installed

```bash
emacsclient --eval "(featurep 'vulpea)"
```

Should return `t`. If not, install vulpea in Emacs.

### Find your notes directory

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/claude-orgmode-eval "org-directory"
```

Returns your configured notes directory path (`org-directory`).

### Run diagnostic

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/claude-orgmode-eval "(claude-orgmode-doctor)"
```

This checks your vulpea configuration and database.

## Multi-Daemon Setup

If you run multiple Emacs configurations (e.g., custom Emacs and Doom Emacs), each can run as a named daemon with its own socket:

```bash
# Start named daemons
emacs --init-directory ~/.config/myemacs --fg-daemon=myemacs
emacs --init-directory ~/.config/doom --fg-daemon=doom
```

Use `-s` to target a specific daemon with `claude-orgmode-eval`:

```bash
# Target myemacs
${CLAUDE_PLUGIN_ROOT}/scripts/claude-orgmode-eval -s myemacs "(claude-orgmode-doctor)"

# Target doom
${CLAUDE_PLUGIN_ROOT}/scripts/claude-orgmode-eval -s doom "(claude-orgmode-doctor)"
```

To discover available sockets:

```bash
# macOS
ls /var/folders/*/*/T/emacs$(id -u)/ 2>/dev/null

# Linux
ls /run/user/$(id -u)/emacs/ 2>/dev/null || ls /tmp/emacs$(id -u)/ 2>/dev/null
```

Each daemon loads `claude-orgmode` independently on first use. They may have different notes directories and databases.

## Common Setup Issues

### Daemon not running

```bash
emacs --daemon
```

### vulpea not installed

Install vulpea package in Emacs. For Doom:
```elisp
;; In packages.el
(package! vulpea)
```

For vanilla Emacs, use package-install or your preferred package manager.

### vulpea not loaded

Ensure vulpea loads on startup. For Doom, the `+roam2` flag on the `org` module includes vulpea; otherwise add it explicitly to your config.

### Database not initialized

Manually sync:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/claude-orgmode-eval "(vulpea-db-sync-full-scan)"
```

## Upgrading the Skill

When the skill is updated, simply pull the latest version. No configuration changes needed since the package auto-loads from the skill directory.

The auto-load mechanism ensures you're always using the version of `claude-orgmode` that ships with the skill, not a separately installed version.
