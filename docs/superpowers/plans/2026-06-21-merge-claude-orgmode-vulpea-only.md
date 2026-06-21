# Merge claude-orgmode (vulpea-only) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (fresh subagent per task, two-stage review) to implement this plan task-by-task. Git state operations (Phase 1 subtree/mv) are done by the orchestrator directly, not delegated. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vendor `majorgreys/claude-orgmode` into this repo as part of the single `emacs-skills` plugin, preserving upstream git history, then strip every standalone org-roam code path, doc, and test so the org subsystem is vulpea-only.

**Architecture:** `git subtree` import under a temporary prefix to preserve authorship, then `git mv` each piece to its final unified-plugin location (`skills/`, `elisp/`, `scripts/`, `references/` at repo root). The org skills locate their library via `${CLAUDE_PLUGIN_ROOT}` and the eval wrapper self-locates `elisp/` as `scripts/`'s sibling, so placing them at the repo root needs **zero edits** to wiring. Then a vulpea-only refactor collapses the dual-backend `pcase` seam to direct vulpea calls.

**Tech Stack:** Emacs Lisp, vulpea (depends on org-roam transitively), Buttercup + Eldev for tests, Claude Code plugin/marketplace JSON.

---

## Decisions locked (from brainstorming)

| Decision | Choice |
|---|---|
| Packaging | **One unified plugin** — org skills join the existing `emacs-skills` plugin |
| Git history | **git subtree** — preserve majorgreys/Tahir Butt authorship |
| Marketplace gap | **Fix it** — register the 10 currently-unlisted skills too |
| org-roam removal | **Full purge incl. test rewrite** — vulpea-only code, docs, and tests |

## Test strategy (RESOLVED) — mocked vulpea, like upstream

Decided: **mocked-only**. The suite uses in-memory vulpea mocks (upstream already ships these in `claude-orgmode-plugin-test.el`'s `before-each`). Mocked tests set `claude-orgmode--backend` to `'vulpea` directly, bypassing detection, so the suite needs **neither vulpea nor org-roam installed** — the Eldev test dependency on `org-roam` can be dropped. Tests verify dispatch wiring + backend-agnostic helpers, not real vulpea DB behavior; that tradeoff is accepted. Never claim green without running `eldev test` and pasting output.

---

## File Map

**Vendored to repo root (via subtree + `git mv`, unchanged):**
- `elisp/` (11 files) · `scripts/claude-orgmode-eval` · `references/` (4 md) · `test/` · `Eldev` · `LICENSE` · `.gitignore` · `.skillignore`
- `skills/orgmode/` · `skills/notes/` (each with `references/`)
- `.github/workflows/test.yml`

**Modified:**
- `.claude-plugin/marketplace.json` — add org skills + 10 missing; bump version; update description
- `README.md` — add org sections + attribution
- `CLAUDE.md` (vendored) — trim conflicting Git-Workflow/Co-Authored-By section
- `elisp/claude-orgmode-backend.el` — vulpea-only dispatch
- `elisp/claude-orgmode-create.el` — drop org-roam manual-creation path + helpers; sanitize tags before `vulpea-create`
- `elisp/claude-orgmode-doctor.el` — drop org-roam `pcase` branch
- `elisp/claude-orgmode.el` — commentary
- `elisp/claude-orgmode-{utils,tags,section,search,links}.el` — comment/docstring scrub only
- `Eldev` — test dep `org-roam` → `vulpea`
- `references/{troubleshooting,installation,emacsclient-usage,functions}.md` — scrub org-roam
- `skills/notes/SKILL.md`, `skills/orgmode/SKILL.md` — vulpea-only language
- `test/*` — rewrite per Phase-5 decision

**Deleted:**
- `skills/notes/references/org-roam-api.md`
- Vendored `README.md`, `CHANGELOG.md`, `.claude-plugin/marketplace.json` (merged away), `.github/workflows/plugin-validate.yml`, `test/plugin-install-test.sh`

---

## Phase 1 — Vendor with history, restructure to unified layout

- [ ] **1.1** Confirm clean tree + on a feature branch (not `main`):
```bash
cd /Users/liyanan/go/src/github.com/ed/emacs-org-skills
git status --porcelain   # expect empty
git switch -c merge-claude-orgmode-vulpea
```
- [ ] **1.2** Subtree-import full history under a temp prefix (upstream default branch is `master`):
```bash
git subtree add --prefix=.orgmode-import https://github.com/majorgreys/claude-orgmode.git master
```
Expected: a merge commit; `.orgmode-import/` now holds the full upstream tree.
- [ ] **1.3** `git mv` kept pieces to final positions:
```bash
git mv .orgmode-import/skills/orgmode skills/orgmode
git mv .orgmode-import/skills/notes   skills/notes
git mv .orgmode-import/elisp          elisp
git mv .orgmode-import/scripts        scripts
git mv .orgmode-import/references     references
git mv .orgmode-import/test           test
git mv .orgmode-import/Eldev          Eldev
git mv .orgmode-import/LICENSE        LICENSE
git mv .orgmode-import/.gitignore     .gitignore
git mv .orgmode-import/.skillignore   .skillignore
git mv .orgmode-import/CLAUDE.md      CLAUDE.md
git mv .orgmode-import/.github/workflows/test.yml .github/workflows/test.yml
```
- [ ] **1.4** Remove the rest (merged-away / dropped):
```bash
git rm .orgmode-import/.claude-plugin/marketplace.json \
       .orgmode-import/README.md \
       .orgmode-import/CHANGELOG.md \
       .orgmode-import/.github/workflows/plugin-validate.yml \
       .orgmode-import/test/plugin-install-test.sh
rm -rf .orgmode-import && git add -A
```
- [ ] **1.5** Verify `git log --follow skills/orgmode/SKILL.md` reaches upstream commits; verify no `.orgmode-import/` remains.
- [ ] **1.6** Commit: `chore: vendor claude-orgmode into unified plugin layout (history preserved)`

## Phase 2 — Wire the merged plugin (marketplace, README, infra)

- [ ] **2.1** `.claude-plugin/marketplace.json`: in the single `emacs-skills` plugin's `skills` array, append `"./skills/orgmode"`, `"./skills/notes"`, and the 10 missing (`d2, matplotlib, mermaid, plantuml, swiftui-preview, xcode-build-device, xcode-build-simulator, xcode-run-device, xcode-run-simulator, xcode-shared`) → 21 total. Update plugin `description` to mention org-mode/vulpea notes; bump `metadata.version` `1.0.0`→`1.1.0`.
- [ ] **2.2** Validate: `jq . .claude-plugin/marketplace.json >/dev/null && echo OK`, then assert every listed `./skills/<x>` dir exists with a `SKILL.md`.
- [ ] **2.3** `README.md`: add `### /orgmode` and `### /notes` entries (vulpea-only wording), an attribution note ("org skills vendored from majorgreys/claude-orgmode, MIT"), and note the new requirement (vulpea + Emacs daemon).
- [ ] **2.4** Trim vendored `CLAUDE.md`: delete the "## Git Workflow" + "Commit format" sections (conflict with global CLAUDE.md: no Co-Authored-By, `main` not `master`); rescope intro to say it documents the org/vulpea subsystem within this repo.
- [ ] **2.5** Commit: `feat: register org + previously-unlisted skills in marketplace; docs`

## Phase 3 — Vulpea-only elisp refactor (TDD where tests exist)

> Order matters: `backend.el` first (the seam), then its consumers. After each file, byte-compile to catch breakage: `emacs -Q --batch -L elisp -f batch-byte-compile elisp/<file>.el` (warnings about unresolved vulpea functions are expected until vulpea is on the load-path; treat *errors* as failures).

- [ ] **3.1 `backend.el`** — `claude-orgmode--detect-backend` returns `'vulpea` (error if vulpea unavailable):
```elisp
(defun claude-orgmode--detect-backend ()
  "Return the active backend.  Vulpea is the only supported backend.
Signals an error if vulpea is not available."
  (or claude-orgmode--backend
      (setq claude-orgmode--backend
            (if (or (featurep 'vulpea) (require 'vulpea nil 'noerror))
                'vulpea
              (error "vulpea is not available")))))
```
Remove `claude-orgmode--backend-org-roam-p`. Keep `claude-orgmode--backend-vulpea-p` (now always non-nil). Collapse every `pcase`/`cond` to its vulpea body (`--backend-directory`, `--db-sync`, `--node-list`, all accessors, `--node-from-id/title`, `--get-backlinks`, `--add-tag`→`vulpea-tags-add`, `--remove-tag`→`vulpea-tags-remove`, `--create-note`, `--info`). Update the file Commentary.
- [ ] **3.2 `create.el`** — make `claude-orgmode-create-note` vulpea-only and **sanitize tags** (preserves the no-hyphens guarantee the org-roam path used to provide):
```elisp
;;;###autoload
(cl-defun claude-orgmode-create-note (title &key tags content content-file keep-file)
  "Create a vulpea note with TITLE, optional TAGS and CONTENT.
TAGS is a list of strings (hyphens are sanitized to underscores).
CONTENT-FILE (path) takes priority over CONTENT and is deleted after
use unless KEEP-FILE is non-nil and it looks like a temp file.
Return the file path of the created note."
  (let* ((actual-content (cond (content-file (claude-orgmode--read-content-file content-file))
                               (content content)
                               (t nil)))
         (clean-tags (mapcar #'claude-orgmode--sanitize-tag (or tags '())))
         (note (vulpea-create title nil :tags clean-tags :body (or actual-content ""))))
    (when (and content-file (not keep-file) (file-exists-p content-file)
               (claude-orgmode--looks-like-temp-file content-file))
      (ignore-errors (delete-file content-file)))
    (vulpea-note-path note)))
```
Delete `claude-orgmode--get-filename-format`, `--expand-filename`, `--get-head-content` (org-roam capture-template only). Keep `claude-orgmode-create-note-with-content` alias. (`--sanitize-tag`, `--read-content-file`, `--looks-like-temp-file`, `--expand-time-formats` stay in `core.el`.)
- [ ] **3.3 `doctor.el`** — delete the `'org-roam` `pcase` clause (the vulpea clause + backend-agnostic checks remain). Update Commentary "Supports both…" → "vulpea backend".
- [ ] **3.4 `claude-orgmode.el`** — Commentary: drop "supporting both org-roam and vulpea" / "Auto-detect" lines; say "vulpea backend".
- [ ] **3.5 comment scrubs** — `utils.el`, `tags.el`, `search.el`, `links.el` line-10 docstrings "Supports both org-roam and vulpea backends" → "Vulpea backend."; `section.el:64` comment "org-id/org-roam convention" → "org-id convention".
- [ ] **3.6** Commit: `refactor: make org note backend vulpea-only`

## Phase 4 — Docs scrub

- [ ] **4.1** `git rm skills/notes/references/org-roam-api.md`
- [ ] **4.2** `skills/notes/SKILL.md`: remove org-roam mentions; change "backend (org-roam or vulpea) is auto-detected — the API is identical" → vulpea statement; remove the `org-roam-api.md` bullet (keep `vulpea-api.md`).
- [ ] **4.3** `skills/orgmode/SKILL.md:13`: "use the **org-roam** or **vulpea** skills" → "use the **notes** skill".
- [ ] **4.4** `references/{troubleshooting,installation,emacsclient-usage,functions}.md`: remove org-roam-specific sections/rows; keep vulpea. (Parallelizable — may dispatch one subagent per file.)
- [ ] **4.5** Commit: `docs: scrub org-roam from org skill references`

## Phase 5 — Test rewrite (mocked vulpea)

- [ ] **5.1 `Eldev`:** drop the org-roam test dep — change `(eldev-add-extra-dependencies 'test 'org-roam 'org-download)` to `(eldev-add-extra-dependencies 'test 'org-download)`. Mocked tests need no backend installed. Update the adjacent comment.
- [ ] **5.2 `test/test-helper.el`:** replace the org-roam temp-DB harness with a reusable in-memory vulpea mock harness (lift the `fset` mock store + accessors from `claude-orgmode-plugin-test.el`'s `before-each`). Provide `claude-orgmode-test--setup`/`--teardown` that install the mocks, set `claude-orgmode--backend` to `'vulpea`, and reset on teardown; keep `--count-nodes`, `--get-note-content`, `--node-exists-p`. Remove `(require 'org-roam)`.
- [ ] **5.3 `claude-orgmode-test.el`:** keep backend-agnostic suites (`--sanitize-tag`, `--validate-org-syntax`, `--read-content-file`, `--looks-like-temp-file`, `--expand-time-formats`). **Delete** org-roam-only suites (`--expand-filename`/capture-template, dual-backend detection, `--backend-org-roam-p`, real-org-roam dispatch / `--with-node-context-by-id` / `create-note` capture-template tests, `check-org-roam-setup` expecting `'org-roam`). Keep & extend the existing **mocked** vulpea dispatch suite. Add a regression test (mocked): `claude-orgmode-create-note` with `:tags '("my-tag")` passes `"my_tag"` to `vulpea-create`.
- [ ] **5.4 `claude-orgmode-integration-test.el`:** rebuild on the mocked `test-helper`. The public-API suites (create/search/tags/links/orphans/graph-stats) run against the in-memory store. **Section-editing tests** (`get/create/replace/append/delete-section`) write real `.org` files into a temp dir and operate by ID — keep them but point file writes at a `test-helper`-provided temp dir var instead of `org-roam-directory`; they exercise real buffer/section logic and don't need a backend DB beyond `--backend-node-from-id` (mock it to read the temp files, or have the section suite use its own temp-dir + `vulpea-db-get-by-id` mock keyed to written IDs). Adjust `#+title:` case assertions to the mock's emitted output.
- [ ] **5.5 `claude-orgmode-plugin-test.el`:** update "plugin structure" asserts to the merged `marketplace.json` (marketplace `name`, skills length = 21, org skill dirs present) or trim to what still holds; drop `claude-orgmode--backend-org-roam-p` from the dispatch-fn list; drop the references-exist check rows that no longer match; delete the real-org-roam full-workflow `describe` (the mocked vulpea workflow covers it). Keep "all modules load" / "public API defined" / mocked vulpea workflow.
- [ ] **5.6** Update `test/README.md` (drop org-roam framing, describe the mocked vulpea suite).
- [ ] **5.7** Run full suite: `eldev -C --unstable test` — **paste real output.** Then `eldev -C --unstable lint`.
- [ ] **5.8** Commit: `test: rewrite org note suite onto vulpea (mocked)`

## Phase 6 — Final verification

- [ ] **6.1** `jq . .claude-plugin/marketplace.json` valid; every listed skill dir has `SKILL.md`.
- [ ] **6.2** `grep -rn 'CLAUDE_PLUGIN_ROOT' skills/notes/SKILL.md` paths resolve: `scripts/claude-orgmode-eval`, `references/*.md`, `elisp/` all exist at repo root.
- [ ] **6.3** Collision check: `grep -rn` that no pre-existing (non-org) skill referenced a root `scripts/`/`elisp/`/`references/` that now clashes.
- [ ] **6.4** Residual org-roam sweep: `grep -rniw org-roam` across `elisp/ skills/ references/ scripts/ test/ README.md CLAUDE.md` — only acceptable hits are explanatory (e.g. "vulpea is built on org-roam") or in `LICENSE`/git history. List remaining hits and justify each.
- [ ] **6.5** `eldev test` green (output pasted). Optionally smoke-test against the user's live vulpea daemon via `scripts/claude-orgmode-eval "(claude-orgmode-doctor)"` (read-only).
- [ ] **6.6** Final commit / ready for `finishing-a-development-branch`.

---

## Risks & mitigations
- **Mocked tests verify wiring, not real vulpea DB behavior** → accepted tradeoff (user choice). Suite stays fully verifiable offline; live behavior smoke-tested once in 6.5 against the user's daemon.
- **Section-editing tests touch real files** → keep them on a temp dir; they're backend-light (operate by ID on written `.org`).
- **Tag sanitization regression** → explicitly re-added in 3.2 + covered by a mocked test in 5.3.
- **Subtree history vs unified layout tension** → accepted; `git mv` keeps `--follow` history, at the cost of future `git subtree pull`.
- **Marketplace identity** (name `xenodium-emacs-skills`, plugin `emacs-skills`) left as-is — rename is out of scope, offered as a follow-up.

## Self-review notes
- Spec coverage: all four locked decisions have phases (merge=1, marketplace gap=2.1, vulpea purge=3–4, test rewrite=5). ✓
- Test strategy resolved to mocked-only; Phase 5 has no hidden placeholders. ✓
- Helper locations verified in `core.el`; backend seam verified in `backend.el`; tag-sanitization gap verified in `create.el`/`tags.el`. ✓
