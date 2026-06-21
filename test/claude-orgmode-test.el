;;; claude-orgmode-test.el --- Unit tests for claude-orgmode -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for claude-orgmode functions using Buttercup.
;;
;; Backend-agnostic helpers (sanitization, time-format expansion, org-syntax
;; validation, content-file reading, temp-file detection) are tested directly.
;; Backend dispatch is tested against the mocked vulpea API (see test-helper.el).

;;; Code:

(require 'buttercup)
(require 'claude-orgmode)
(require 'test-helper)

;; Declare vulpea variables special so `let' binds them dynamically even under
;; lexical-binding (the backend probes them with `boundp'/reads them globally).
(defvar vulpea-db-sync-directories)
(defvar vulpea-db-location)

;;; Tag Sanitization Tests

(describe "claude-orgmode--sanitize-tag"
  (it "replaces hyphens with underscores"
    (expect (claude-orgmode--sanitize-tag "my-tag") :to-equal "my_tag"))

  (it "handles multi-word tags"
    (expect (claude-orgmode--sanitize-tag "multi-word-tag") :to-equal "multi_word_tag"))

  (it "leaves already clean tags unchanged"
    (expect (claude-orgmode--sanitize-tag "already_clean") :to-equal "already_clean")
    (expect (claude-orgmode--sanitize-tag "no_change") :to-equal "no_change")))

;;; Time Format Expansion Tests

(describe "claude-orgmode--expand-time-formats"
  (it "expands custom time format %<...>"
    (let ((result (claude-orgmode--expand-time-formats "Date: %<%Y-%m-%d>")))
      (expect result :to-match "Date: [0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}")))

  (it "expands %U inactive timestamp with time"
    (let ((result (claude-orgmode--expand-time-formats "Created: %U")))
      (expect result :to-match "Created: \\[[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [A-Z][a-z][a-z] [0-9]\\{2\\}:[0-9]\\{2\\}\\]")))

  (it "expands %u inactive timestamp without time"
    (let ((result (claude-orgmode--expand-time-formats "Date: %u")))
      (expect result :to-match "Date: \\[[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [A-Z][a-z][a-z]\\]")))

  (it "expands %T active timestamp with time"
    (let ((result (claude-orgmode--expand-time-formats "Scheduled: %T")))
      (expect result :to-match "Scheduled: <[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [A-Z][a-z][a-z] [0-9]\\{2\\}:[0-9]\\{2\\}>")))

  (it "expands %t active timestamp without time"
    (let ((result (claude-orgmode--expand-time-formats "Deadline: %t")))
      (expect result :to-match "Deadline: <[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [A-Z][a-z][a-z]>")))

  (it "expands multiple time formats in one string"
    (let ((result (claude-orgmode--expand-time-formats "#+date: %<%Y-%m-%d>\n#+created: %U")))
      (expect result :to-match "^#\\+date: [0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}")
      (expect result :to-match "#\\+created: \\[[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}")))

  (it "leaves text without time formats unchanged"
    (let ((result (claude-orgmode--expand-time-formats "Just plain text")))
      (expect result :to-equal "Just plain text"))))

;;; Org Syntax Validation Tests

(describe "claude-orgmode--validate-org-syntax"
  (it "validates proper org syntax"
    (let ((test-file (make-temp-file "claude-orgmode-test-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file test-file
              (insert ":PROPERTIES:\n")
              (insert ":ID:       test-id\n")
              (insert ":END:\n")
              (insert "#+TITLE: Test Note\n")
              (insert "#+FILETAGS: :test:\n"))
            (let ((result (claude-orgmode--validate-org-syntax test-file)))
              (expect (plist-get result :valid) :to-be t)
              (expect (plist-get result :errors) :to-equal nil)))
        (when (file-exists-p test-file)
          (delete-file test-file)))))

  (it "detects lowercase keywords"
    (let ((test-file (make-temp-file "claude-orgmode-test-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file test-file
              (insert ":PROPERTIES:\n")
              (insert ":ID:       test-id\n")
              (insert ":END:\n")
              (insert "#+title: Test Note\n"))
            (let ((result (claude-orgmode--validate-org-syntax test-file)))
              (expect (plist-get result :valid) :to-be nil)
              (expect (length (plist-get result :errors)) :to-be-greater-than 0)))
        (when (file-exists-p test-file)
          (delete-file test-file)))))

  (it "detects blank lines in PROPERTIES drawer"
    (let ((test-file (make-temp-file "claude-orgmode-test-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file test-file
              (insert ":PROPERTIES:\n")
              (insert ":ID:       test-id\n")
              (insert "\n")  ;; Blank line - should be detected
              (insert ":END:\n")
              (insert "#+TITLE: Test Note\n"))
            (let ((result (claude-orgmode--validate-org-syntax test-file)))
              (expect (plist-get result :valid) :to-be nil)
              (expect (car (plist-get result :errors)) :to-match "PROPERTIES drawer contains blank lines")))
        (when (file-exists-p test-file)
          (delete-file test-file)))))

  (it "detects headings without space after asterisks"
    (let ((test-file (make-temp-file "claude-orgmode-test-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file test-file
              (insert ":PROPERTIES:\n")
              (insert ":ID:       test-id\n")
              (insert ":END:\n")
              (insert "#+TITLE: Test Note\n")
              (insert "*Heading without space\n"))
            (let ((result (claude-orgmode--validate-org-syntax test-file)))
              (expect (plist-get result :valid) :to-be nil)
              (expect (car (plist-get result :errors)) :to-match "missing space after asterisks")))
        (when (file-exists-p test-file)
          (delete-file test-file))))))

;;; Content File Reading Tests

(describe "claude-orgmode--read-content-file"
  (it "reads content from existing file"
    (let ((test-file (make-temp-file "claude-orgmode-test-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file test-file
              (insert "Test content from file"))
            (expect (claude-orgmode--read-content-file test-file)
                    :to-equal "Test content from file"))
        (when (file-exists-p test-file)
          (delete-file test-file)))))

  (it "signals error for non-existent file"
    (expect (claude-orgmode--read-content-file "/nonexistent/file.org")
            :to-throw 'error))

  (it "handles files with special characters"
    (let ((test-file (make-temp-file "claude-orgmode-test-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file test-file
              (insert "Content with \"quotes\" and 'apostrophes' and $special chars"))
            (expect (claude-orgmode--read-content-file test-file)
                    :to-match "quotes"))
        (when (file-exists-p test-file)
          (delete-file test-file)))))

  (it "handles large files"
    (let ((test-file (make-temp-file "claude-orgmode-test-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file test-file
              (dotimes (i 1000)
                (insert (format "Line %d with content\n" i))))
            (let ((content (claude-orgmode--read-content-file test-file)))
              (expect (length content) :to-be-greater-than 10000)
              (expect content :to-match "Line 999")))
        (when (file-exists-p test-file)
          (delete-file test-file))))))

;;; Note Creation Tests (mocked vulpea backend)

(describe "claude-orgmode-create-note"
  (before-each (claude-orgmode-test--setup))
  (after-each (claude-orgmode-test--teardown))

  (it "creates notes with inline content using :content parameter"
    (let ((file-path (claude-orgmode-create-note "Test Note"
                                                 :tags '("test" "example")
                                                 :content "Test content")))
      (expect (file-exists-p file-path) :to-be t)
      (with-temp-buffer
        (insert-file-contents file-path)
        (let ((content (buffer-string)))
          (expect (string-match-p "Test content" content) :to-be-truthy)
          (expect (string-match-p "#\\+\\(?:TITLE\\|title\\):" content) :to-be-truthy)
          (expect (string-match-p "#\\+\\(?:FILETAGS\\|filetags\\):" content) :to-be-truthy)
          (expect (string-match-p ":PROPERTIES:" content) :to-be-truthy)
          (expect (string-match-p ":ID:" content) :to-be-truthy)
          (expect (string-match-p ":END:" content) :to-be-truthy)))))

  (it "creates notes with content from file using :content-file parameter"
    (let ((content-file (make-temp-file "claude-orgmode-content-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file content-file
              (insert "# Content from File\n\nThis is test content loaded from a temporary file."))
            (let ((file-path (claude-orgmode-create-note "Test Note From File"
                                                         :tags '("test" "file")
                                                         :content-file content-file)))
              (expect (file-exists-p file-path) :to-be t)
              (with-temp-buffer
                (insert-file-contents file-path)
                (let ((content (buffer-string)))
                  (expect (string-match-p "Content from File" content) :to-be-truthy)
                  (expect (string-match-p "test content loaded from" content) :to-be-truthy)
                  (expect (string-match-p "#\\+\\(?:TITLE\\|title\\):" content) :to-be-truthy)
                  (expect (string-match-p ":test:file:" content) :to-be-truthy)))))
        (when (file-exists-p content-file)
          (delete-file content-file)))))

  (it "prioritizes :content-file over :content when both provided"
    (let ((content-file (make-temp-file "claude-orgmode-content-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file content-file
              (insert "Content from file should win"))
            (let ((file-path (claude-orgmode-create-note "Priority Test"
                                                         :content "Inline content"
                                                         :content-file content-file)))
              (expect (file-exists-p file-path) :to-be t)
              (with-temp-buffer
                (insert-file-contents file-path)
                (let ((content (buffer-string)))
                  (expect content :to-match "Content from file should win")
                  (expect content :not :to-match "Inline content")))))
        (when (file-exists-p content-file)
          (delete-file content-file)))))

  (it "sanitizes hyphenated tags before passing them to vulpea-create"
    ;; Regression guard: create-note must sanitize ("my-tag" -> "my_tag")
    ;; *before* delegating to vulpea-create.
    (spy-on 'vulpea-create :and-call-through)
    (claude-orgmode-create-note "Sanitize Test" :tags '("my-tag" "two-words"))
    (expect 'vulpea-create :to-have-been-called)
    (let* ((args (spy-calls-args-for 'vulpea-create 0))
           (passed-tags (plist-get (cddr args) :tags)))
      (expect passed-tags :to-equal '("my_tag" "two_words")))))

;;; Temp File Detection Tests

(describe "claude-orgmode--looks-like-temp-file"
  (it "returns t for /tmp/ paths"
    (expect (claude-orgmode--looks-like-temp-file "/tmp/test.org") :to-be-truthy))

  (it "returns t for /var/tmp/ paths"
    (expect (claude-orgmode--looks-like-temp-file "/var/tmp/test.org") :to-be-truthy))

  (it "returns nil for home directory paths"
    (expect (claude-orgmode--looks-like-temp-file "~/test.org") :not :to-be-truthy))

  (it "returns nil for absolute home directory paths"
    (expect (claude-orgmode--looks-like-temp-file (expand-file-name "~/test.org")) :not :to-be-truthy))

  (it "returns nil for non-strings"
    (expect (claude-orgmode--looks-like-temp-file nil) :not :to-be-truthy)
    (expect (claude-orgmode--looks-like-temp-file 123) :not :to-be-truthy)))

;;; Temp File Cleanup Tests (mocked vulpea backend)
;;
;; The content-file cleanup logic in `claude-orgmode-create-note' is
;; backend-agnostic; exercise it with the mocked backend so a real note file is
;; produced without needing a real vulpea install.

(describe "claude-orgmode-create-note with temp file cleanup"
  (before-each (claude-orgmode-test--setup))
  (after-each (claude-orgmode-test--teardown))

  (it "automatically deletes temp file after note creation"
    (let ((temp-file (make-temp-file "claude-orgmode-tmp-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file temp-file
              (insert "Test content"))
            (let ((file-path (claude-orgmode-create-note "Temp File Test"
                                                         :content-file temp-file)))
              (expect (file-exists-p file-path) :to-be t)
              ;; Temp file should be auto-deleted
              (expect (file-exists-p temp-file) :not :to-be-truthy)))
        (when (file-exists-p temp-file)
          (delete-file temp-file)))))

  (it "preserves temp file when :keep-file is t"
    (let ((temp-file (make-temp-file "claude-orgmode-tmp-" nil ".org")))
      (unwind-protect
          (progn
            (with-temp-file temp-file
              (insert "Test content"))
            (let ((file-path (claude-orgmode-create-note "Keep File Test"
                                                         :content-file temp-file
                                                         :keep-file t)))
              (expect (file-exists-p file-path) :to-be t)
              ;; Temp file should NOT be deleted when :keep-file is t
              (expect (file-exists-p temp-file) :to-be t)))
        (when (file-exists-p temp-file)
          (delete-file temp-file)))))

  (it "handles direct content without a temp file gracefully"
    ;; Should not throw when no content-file is given.
    (expect (claude-orgmode-create-note "Direct Content Test"
                                        :content "Direct content")
            :not :to-throw)))

;;; Backend Detection Tests (mocked vulpea)

(describe "claude-orgmode--detect-backend"
  (after-each (setq claude-orgmode--backend nil))

  (it "returns vulpea when vulpea is available"
    (let ((claude-orgmode--backend nil))
      ;; Mocked environment: pretend vulpea is loaded.
      (spy-on 'featurep :and-call-fake
              (lambda (feature &rest _) (eq feature 'vulpea)))
      (expect (claude-orgmode--detect-backend) :to-be 'vulpea)))

  (it "caches the detected backend"
    (let ((claude-orgmode--backend nil))
      (spy-on 'featurep :and-call-fake
              (lambda (feature &rest _) (eq feature 'vulpea)))
      (claude-orgmode--detect-backend)
      (expect claude-orgmode--backend :to-be 'vulpea)))

  (it "returns cached value on subsequent calls"
    (let ((claude-orgmode--backend 'vulpea))
      (expect (claude-orgmode--detect-backend) :to-be 'vulpea))))

(describe "claude-orgmode--backend-vulpea-p"
  (it "returns non-nil when backend is vulpea"
    (let ((claude-orgmode--backend 'vulpea))
      (expect (claude-orgmode--backend-vulpea-p) :to-be-truthy))))

;;; Vulpea Backend Dispatch Tests (mocked)
;;
;; vulpea is not available in the test environment, so we mock the vulpea API
;; and verify that each backend dispatch function calls the correct vulpea
;; function with the correct arguments when the backend is `vulpea'.

(describe "vulpea backend dispatch"
  :var (mock-note)

  (before-each
    ;; A mock vulpea note (just a plist).
    (setq mock-note '(:id "vulpea-uuid-123"
                      :title "Vulpea Test Note"
                      :path "/notes/test.org"
                      :tags ("emacs" "lisp")
                      :aliases ("VTN")
                      :level 0))

    ;; Mock vulpea functions returning predictable values.
    (fset 'vulpea-note-id (lambda (note) (plist-get note :id)))
    (fset 'vulpea-note-title (lambda (note) (plist-get note :title)))
    (fset 'vulpea-note-path (lambda (note) (plist-get note :path)))
    (fset 'vulpea-note-tags (lambda (note) (plist-get note :tags)))
    (fset 'vulpea-note-aliases (lambda (note) (plist-get note :aliases)))
    (fset 'vulpea-note-level (lambda (note) (plist-get note :level)))
    (fset 'vulpea-db-get-by-id (lambda (id) (when (equal id "vulpea-uuid-123") mock-note)))
    (fset 'vulpea-db-search-by-title (lambda (title) (when (equal title "Vulpea Test Note") (list mock-note))))
    (fset 'vulpea-db-query (lambda () (list mock-note)))
    (fset 'vulpea-db-sync-full-scan (lambda () t))
    (fset 'vulpea-tags-add (lambda (_note _tag) t))
    (fset 'vulpea-tags-remove (lambda (_note _tag) t))
    (fset 'vulpea-db-query-links-to (lambda (_id) nil))
    (fset 'vulpea-create (lambda (_title _meta &rest _args) mock-note)))

  (describe "claude-orgmode--backend-node-id"
    (it "dispatches to vulpea-note-id"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-note-id :and-call-through)
        (expect (claude-orgmode--backend-node-id mock-note)
                :to-equal "vulpea-uuid-123")
        (expect 'vulpea-note-id :to-have-been-called-with mock-note))))

  (describe "claude-orgmode--backend-node-title"
    (it "dispatches to vulpea-note-title"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-note-title :and-call-through)
        (expect (claude-orgmode--backend-node-title mock-note)
                :to-equal "Vulpea Test Note")
        (expect 'vulpea-note-title :to-have-been-called-with mock-note))))

  (describe "claude-orgmode--backend-node-file"
    (it "dispatches to vulpea-note-path"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-note-path :and-call-through)
        (expect (claude-orgmode--backend-node-file mock-note)
                :to-equal "/notes/test.org")
        (expect 'vulpea-note-path :to-have-been-called-with mock-note))))

  (describe "claude-orgmode--backend-node-tags"
    (it "dispatches to vulpea-note-tags"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-note-tags :and-call-through)
        (expect (claude-orgmode--backend-node-tags mock-note)
                :to-equal '("emacs" "lisp"))
        (expect 'vulpea-note-tags :to-have-been-called-with mock-note))))

  (describe "claude-orgmode--backend-node-aliases"
    (it "dispatches to vulpea-note-aliases"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-note-aliases :and-call-through)
        (expect (claude-orgmode--backend-node-aliases mock-note)
                :to-equal '("VTN"))
        (expect 'vulpea-note-aliases :to-have-been-called-with mock-note))))

  (describe "claude-orgmode--backend-node-level"
    (it "dispatches to vulpea-note-level"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-note-level :and-call-through)
        (expect (claude-orgmode--backend-node-level mock-note)
                :to-equal 0)
        (expect 'vulpea-note-level :to-have-been-called-with mock-note))))

  (describe "claude-orgmode--backend-node-from-id"
    (it "dispatches to vulpea-db-get-by-id"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-db-get-by-id :and-call-through)
        (expect (claude-orgmode--backend-node-from-id "vulpea-uuid-123")
                :to-equal mock-note)
        (expect 'vulpea-db-get-by-id :to-have-been-called-with "vulpea-uuid-123"))))

  (describe "claude-orgmode--backend-node-from-title"
    (it "dispatches to vulpea-db-search-by-title"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-db-search-by-title :and-call-through)
        (expect (claude-orgmode--backend-node-from-title "Vulpea Test Note")
                :to-equal mock-note)
        (expect 'vulpea-db-search-by-title :to-have-been-called-with "Vulpea Test Note"))))

  (describe "claude-orgmode--backend-node-list"
    (it "dispatches to vulpea-db-query"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-db-query :and-call-through)
        (expect (claude-orgmode--backend-node-list)
                :to-equal (list mock-note))
        (expect 'vulpea-db-query :to-have-been-called))))

  (describe "claude-orgmode--backend-db-sync"
    (it "dispatches to vulpea-db-sync-full-scan"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-db-sync-full-scan :and-call-through)
        (claude-orgmode--backend-db-sync)
        (expect 'vulpea-db-sync-full-scan :to-have-been-called))))

  (describe "claude-orgmode--backend-get-backlinks"
    (it "dispatches to vulpea-db-query-links-to"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-db-query-links-to :and-call-through)
        (expect (claude-orgmode--backend-get-backlinks mock-note)
                :to-equal nil)
        (expect 'vulpea-db-query-links-to :to-have-been-called-with "vulpea-uuid-123"))))

  (describe "claude-orgmode--backend-add-tag"
    (it "dispatches to vulpea-tags-add"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-tags-add :and-call-through)
        (claude-orgmode--backend-add-tag mock-note "new_tag")
        (expect 'vulpea-tags-add :to-have-been-called-with mock-note "new_tag"))))

  (describe "claude-orgmode--backend-remove-tag"
    (it "dispatches to vulpea-tags-remove"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-tags-remove :and-call-through)
        (claude-orgmode--backend-remove-tag mock-note "old_tag")
        (expect 'vulpea-tags-remove :to-have-been-called-with mock-note "old_tag"))))

  (describe "claude-orgmode--backend-create-note"
    (it "dispatches to vulpea-create and returns the note path"
      (let ((claude-orgmode--backend 'vulpea))
        (spy-on 'vulpea-create :and-call-through)
        (expect (claude-orgmode--backend-create-note "New Note"
                                                     :tags '("a")
                                                     :content "body")
                :to-equal "/notes/test.org")
        (expect 'vulpea-create :to-have-been-called))))

  (describe "claude-orgmode--backend-directory"
    (it "returns vulpea directory from vulpea-db-sync-directories"
      (let ((claude-orgmode--backend 'vulpea)
            (vulpea-db-sync-directories '("/vulpea/notes")))
        (expect (claude-orgmode--backend-directory)
                :to-equal "/vulpea/notes")))

    (it "falls back to org-directory when vulpea-db-sync-directories unbound"
      (let ((claude-orgmode--backend 'vulpea)
            (org-directory "/fallback/org"))
        (when (boundp 'vulpea-db-sync-directories)
          (makunbound 'vulpea-db-sync-directories))
        (expect (claude-orgmode--backend-directory)
                :to-equal "/fallback/org"))))

  (describe "claude-orgmode--backend-info"
    (it "returns vulpea backend info"
      (let ((claude-orgmode--backend 'vulpea)
            (vulpea-db-sync-directories '("/vulpea/notes")))
        (spy-on 'vulpea-db-query :and-return-value (list mock-note))
        (let ((info (claude-orgmode--backend-info)))
          (expect (plist-get info :backend) :to-be 'vulpea)
          (expect (plist-get info :directory) :to-equal "/vulpea/notes")
          (expect (plist-get info :node-count) :to-be 1))))))

;;; Node Context By ID Tests (mocked vulpea)

(describe "claude-orgmode--with-node-context-by-id"
  (before-each (claude-orgmode-test--setup))
  (after-each (claude-orgmode-test--teardown))

  (it "calls function with node when ID exists"
    (let ((test-file (expand-file-name "ctx.org" claude-orgmode-test-directory)))
      (with-temp-file test-file
        (insert ":PROPERTIES:\n:ID:       ctx-by-id-test\n:END:\n#+TITLE: Context Test\n"))
      (claude-orgmode-test--register-note "ctx-by-id-test" test-file 0 "Context Test")
      (let ((result (claude-orgmode--with-node-context-by-id
                     "ctx-by-id-test"
                     (lambda (node)
                       (claude-orgmode--backend-node-title node)))))
        (expect result :to-equal "Context Test"))))

  (it "errors when ID does not exist"
    (expect (claude-orgmode--with-node-context-by-id
             "nonexistent-id"
             (lambda (node) node))
            :to-throw 'error))

  (it "never falls back to title lookup"
    (let ((test-file (expand-file-name "nofallback.org" claude-orgmode-test-directory)))
      (with-temp-file test-file
        (insert ":PROPERTIES:\n:ID:       no-fallback-id\n:END:\n#+TITLE: Fallback Test\n"))
      (claude-orgmode-test--register-note "no-fallback-id" test-file 0 "Fallback Test")
      ;; Passing the title string should error, not find the node.
      (expect (claude-orgmode--with-node-context-by-id
               "Fallback Test"
               (lambda (node) node))
              :to-throw 'error))))

(provide 'claude-orgmode-test)
;;; claude-orgmode-test.el ends here
