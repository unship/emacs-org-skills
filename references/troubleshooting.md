# Troubleshooting Guide

Common issues and solutions for claude-orgmode.

## Connection Issues

### Daemon Not Running

**Symptoms:**
- `emacsclient: can't find socket; have you started the server?`
- Connection refused errors

**Solution:**
```bash
emacs --daemon
```

**Verify:**
```bash
emacsclient --eval "t"
```

Should return `t` without errors.

### Multiple Daemon Instances

Multiple named daemons (e.g., `myemacs` and `server`) are a supported configuration. Each runs independently with its own socket.

**Symptoms of accidentally connecting to the wrong daemon:**
- Functions not found (skill loaded in other daemon)
- Wrong notes directory or database
- Unexpected notes or missing results

**Check running daemons:**
```bash
pgrep -af emacs
```

**Check available sockets:**
```bash
# macOS
ls /var/folders/*/*/T/emacs$(id -u)/ 2>/dev/null

# Linux
ls /run/user/$(id -u)/emacs/ 2>/dev/null || ls /tmp/emacs$(id -u)/ 2>/dev/null
```

**Solution:**
Use `-s` to target the correct daemon:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/claude-orgmode-eval -s myemacs "(claude-orgmode-doctor)"
```

**Verify which daemon you're connected to:**
```bash
emacsclient --socket-name myemacs --eval "(claude-orgmode-doctor)"
emacsclient --socket-name server --eval "(claude-orgmode-doctor)"
```

## Package Loading Issues

### claude-orgmode Not Loaded

**Symptoms:**
- `emacsclient --eval "(featurep 'claude-orgmode)"` returns `nil`
- Function not found errors

**Solution:**

1. Verify load-path is correct:
   ```bash
   ls ${CLAUDE_PLUGIN_ROOT}/elisp/claude-orgmode.el
   ```

2. Check Emacs configuration has correct path:
   ```elisp
   ;; For Doom (replace <PLUGIN_PATH> with actual plugin location)
   (use-package! claude-orgmode
     :load-path "<PLUGIN_PATH>/elisp")

   ;; For vanilla (replace <PLUGIN_PATH> with actual plugin location)
   (add-to-list 'load-path "<PLUGIN_PATH>/elisp")
   (require 'claude-orgmode)
   ```

   Note: `<PLUGIN_PATH>` is the skill's installation directory. The auto-load
   wrapper (`scripts/claude-orgmode-eval`) handles this automatically—manual Emacs
   configuration is only needed if auto-loading fails.

3. Restart Emacs daemon:
   ```bash
   pkill -f "emacs --daemon"
   emacs --daemon
   ```

4. Verify loaded:
   ```bash
   emacsclient --eval "(featurep 'claude-orgmode)"
   ```

### vulpea Not Loaded

**Symptoms:**
- vulpea functions not available
- `(featurep 'vulpea)` returns `nil`

**Verify:**
```bash
emacsclient --eval "(featurep 'vulpea)"
```

**Solution:**

Ensure vulpea is installed and loads on startup. For Doom:
```elisp
;; In packages.el
(package! vulpea)
```

Restart daemon.

## Database Issues

### Database Not Initialized

**Symptoms:**
- Database file doesn't exist
- Empty query results
- "Database is empty" warnings

**Check database:**
```bash
emacsclient --eval "(file-exists-p vulpea-db-location)"
```

**Solution:**
```bash
emacsclient --eval "(vulpea-db-sync-full-scan)"
```

Wait for sync to complete (may take time for large note collections).

### Database Out of Sync

**Symptoms:**
- Recently created notes not appearing in searches
- Stale backlinks
- Missing connections

**Solution:**

Force full resync:
```bash
emacsclient --eval "(vulpea-db-sync-full-scan)"
```

### Database Corruption

**Symptoms:**
- SQL errors
- Crashes when querying
- Incomplete results

**Solution:**

Rebuild database from scratch:
```bash
# Backup first
cp $(emacsclient --eval "vulpea-db-location") ~/vulpea-db-backup.db

# Delete and rebuild
emacsclient --eval "(progn
  (delete-file vulpea-db-location)
  (vulpea-db-sync-full-scan))"
```

## Note Creation Issues

### Tag Formatting Errors

**Symptoms:**
- `wrong-type-argument` errors
- Tags not applied correctly
- `listp` errors

**Problem:**
Tags passed as string instead of list.

**Wrong:**
```bash
emacsclient --eval "(claude-orgmode-create-note \"Title\" :tags \"tag\")"
```

**Correct:**
```bash
emacsclient --eval "(claude-orgmode-create-note \"Title\" :tags '(\"tag\"))"
```

### Content Escaping Issues

**Symptoms:**
- Shell escaping errors
- Partial content
- Special characters broken

**Solution:**

Use `:content-file` instead of `:content` for complex content:

```bash
TEMP=$(mktemp -t orgmode-content.XXXXXX)
cat > "$TEMP" << 'EOF'
Your content with special characters, quotes, etc.
EOF
emacsclient --eval "(claude-orgmode-create-note \"Title\" :content-file \"$TEMP\")"
```

### Content Not Being Formatted

**Symptoms:**
- Markdown content appears as-is in org notes
- Content is not converted to org-mode format

**Explanation:**
This skill does not perform automatic markdown→org conversion. This is intentional to maintain separation of concerns.

**Solution:**

Use the `orgmode` skill for general org-mode formatting before creating notes:

```bash
# Step 1: Convert markdown to org (orgmode skill)
# Step 2: Create note with org content (this skill)
${CLAUDE_PLUGIN_ROOT}/scripts/claude-orgmode-eval \
  "(claude-orgmode-create-note \"Title\" :content \"* Org content\")"
```

This skill focuses on note operations (creation, database sync, node linking). For general org-mode formatting, use the `orgmode` skill.

## Search Issues

### No Results Found

**Symptoms:**
- Search returns empty even for known notes
- Backlinks not appearing

**Solutions:**

1. Sync database:
   ```bash
   emacsclient --eval "(vulpea-db-sync-full-scan)"
   ```

2. Check search term case (searches are case-insensitive):
   ```bash
   emacsclient --eval "(claude-orgmode-search-by-title \"react\")"
   ```

3. Verify notes exist:
   ```bash
   emacsclient --eval "(vulpea-db-query)"
   ```

### Partial Matches Not Working

**Symptoms:**
- Only exact title matches work
- Substring searches fail

**Note:**
`claude-orgmode-search-by-title` does partial matching by default. If not working, check database is synced.

## Link Issues

### Backlinks Not Appearing

**Symptoms:**
- Created links don't show as backlinks
- Connection missing in graph

**Solutions:**

1. Ensure link uses ID format:
   ```org
   [[id:node-uuid][Description]]
   ```

2. Sync database after creating links:
   ```bash
   emacsclient --eval "(vulpea-db-sync-full-scan)"
   ```

3. Verify link was actually inserted:
   ```bash
   emacsclient --eval "(claude-orgmode-get-backlinks-by-title \"Target Note\")"
   ```

### Bidirectional Links Only Go One Way

**Symptoms:**
- Only one direction of link created
- Asymmetric connections

**Check:**
Both notes should have links. Verify via backlinks:
```bash
emacsclient --eval "(claude-orgmode-get-backlinks-by-title \"Note A\")"
emacsclient --eval "(claude-orgmode-get-backlinks-by-title \"Note B\")"
```

Look for `id:` links in both files.

## Performance Issues

### Slow Queries

**Symptoms:**
- Searches take seconds
- Database sync is slow

**Solutions:**

1. Check database size:
   ```bash
   ls -lh $(emacsclient --eval "vulpea-db-location")
   ```

2. For large databases, use specific searches:
   - Use title search instead of content search when possible
   - Use tag filters to narrow results

3. Keep daemon running (avoid repeated startup overhead)

### Memory Usage

**Symptoms:**
- High memory usage
- Daemon crashes

**Solution:**

Restart daemon periodically:
```bash
pkill -f "emacs --daemon"
emacs --daemon
```

## Permission Issues

### Cannot Write to Notes Directory

**Symptoms:**
- "Permission denied" when creating notes
- Cannot create files

**Check permissions:**
```bash
ls -ld $(emacsclient --eval "org-directory")
```

**Solution:**
```bash
chmod 755 ~/Documents/org
```

### Database Not Writable

**Symptoms:**
- Cannot sync database
- Read-only database errors

**Check:**
```bash
ls -l $(emacsclient --eval "vulpea-db-location")
```

**Fix:**
```bash
chmod 644 $(emacsclient --eval "vulpea-db-location")
```

## Diagnostic Commands

### Full System Check

Run comprehensive diagnostic:
```bash
emacsclient --eval "(claude-orgmode-doctor)"
```

Checks:
- Emacs version
- vulpea version
- Directory exists and accessible
- Database status

### Check Package Status

```bash
# Check claude-orgmode loaded
emacsclient --eval "(featurep 'claude-orgmode)"

# Check vulpea loaded
emacsclient --eval "(featurep 'vulpea)"

# Check database exists
emacsclient --eval "(file-exists-p vulpea-db-location)"

# Check notes directory configured
emacsclient --eval "org-directory"
```

### Get System Info

```bash
# Emacs version
emacsclient --eval "(emacs-version)"

# vulpea version
emacsclient --eval "(pkg-info-version-info 'vulpea)"

# Database path
emacsclient --eval "vulpea-db-location"
```

## Getting Help

If issues persist:

1. **Run diagnostic**: `emacsclient --eval "(claude-orgmode-doctor)"`
2. **Check logs**: Look for errors in `*Messages*` buffer
3. **Verify setup**: Ensure all prerequisites are met (see references/installation.md)
4. **Restart daemon**: Often resolves transient issues
5. **Check vulpea documentation**: Many issues are vulpea-specific, not skill-specific
