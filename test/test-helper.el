;;; test-helper.el --- Test utilities for claude-orgmode -*- lexical-binding: t; -*-

;;; Commentary:
;; Shared test fixtures and utilities using Buttercup.
;;
;; The suite is MOCKED: there is no real vulpea / org-roam install.  We force
;; the backend to `vulpea' and `fset' an in-memory note store in place of the
;; vulpea API.  `vulpea-create' writes a real `.org' file into a per-test temp
;; directory (so `file-exists-p', content assertions, and the section-editing
;; code that re-opens the file all work) and records a note plist in the store.
;;
;; A note plist has the shape:
;;   (:id ID :title TITLE :path PATH :tags TAGS :aliases ALIASES :level LEVEL)

;;; Code:

(require 'buttercup)
(require 'cl-lib)
(require 'claude-orgmode)

;; Declare vulpea variables special so `let' binds them dynamically even under
;; lexical-binding (production code probes them with `boundp').
(defvar vulpea-db-sync-directories)
(defvar vulpea-db-location)

(defvar claude-orgmode-test-directory nil
  "Temporary directory holding notes created during a test.")

(defvar claude-orgmode-test--note-store nil
  "In-memory note store: maps note ID string -> note plist.")

(defvar claude-orgmode-test--note-counter 0
  "Counter used to mint unique note IDs in the mock `vulpea-create'.")

;;; Mock installation

(defun claude-orgmode-test--install-mocks ()
  "Install in-memory `fset' mocks for the vulpea API."
  ;; Note accessors
  (fset 'vulpea-note-id (lambda (note) (plist-get note :id)))
  (fset 'vulpea-note-title (lambda (note) (plist-get note :title)))
  (fset 'vulpea-note-path (lambda (note) (plist-get note :path)))
  (fset 'vulpea-note-tags (lambda (note) (plist-get note :tags)))
  (fset 'vulpea-note-aliases (lambda (note) (plist-get note :aliases)))
  (fset 'vulpea-note-level (lambda (note) (plist-get note :level)))

  ;; Queries against the in-memory store
  (fset 'vulpea-db-query
        (lambda ()
          (let (notes)
            (maphash (lambda (_k v) (push v notes)) claude-orgmode-test--note-store)
            notes)))

  (fset 'vulpea-db-get-by-id
        (lambda (id) (gethash id claude-orgmode-test--note-store)))

  (fset 'vulpea-db-search-by-title
        (lambda (title)
          (let (results)
            (maphash (lambda (_k v)
                       (when (or (equal (plist-get v :title) title)
                                 (member title (plist-get v :aliases)))
                         (push v results)))
                     claude-orgmode-test--note-store)
            results)))

  (fset 'vulpea-db-sync-full-scan (lambda () t))

  ;; Link graph, derived from real file content (as a real vulpea DB sync
  ;; would): return one (:source SOURCE-ID) plist for every stored note whose
  ;; file body contains an [[id:TARGET-ID]...]] link to the queried ID.
  (fset 'vulpea-db-query-links-to
        (lambda (id)
          (let (links)
            (maphash
             (lambda (source-id source-note)
               (let ((path (plist-get source-note :path)))
                 (when (and path (file-exists-p path)
                            (not (equal source-id id)))
                   (with-temp-buffer
                     (insert-file-contents path)
                     (goto-char (point-min))
                     (when (re-search-forward
                            (format "\\[\\[id:%s\\]" (regexp-quote id)) nil t)
                       (push (list :source source-id :dest id) links))))))
             claude-orgmode-test--note-store)
            links)))

  ;; Tag mutation writes back into the store AND rewrites the on-disk
  ;; #+FILETAGS: line so content assertions on the file see the change.
  (fset 'vulpea-tags-add
        (lambda (note tag)
          (let* ((id (plist-get note :id))
                 (existing (gethash id claude-orgmode-test--note-store)))
            (when existing
              (let ((tags (plist-get note :tags)))
                (unless (member tag tags)
                  (setq existing (plist-put existing :tags (append tags (list tag))))
                  (puthash id existing claude-orgmode-test--note-store)
                  (claude-orgmode-test--rewrite-filetags existing)))))))

  (fset 'vulpea-tags-remove
        (lambda (note tag)
          (let* ((id (plist-get note :id))
                 (existing (gethash id claude-orgmode-test--note-store)))
            (when existing
              (let ((tags (plist-get note :tags)))
                (setq existing (plist-put existing :tags (remove tag tags)))
                (puthash id existing claude-orgmode-test--note-store)
                (claude-orgmode-test--rewrite-filetags existing))))))

  ;; Note creation: write a real .org file, record the note.
  (fset 'vulpea-create
        (lambda (title _meta &rest args)
          (let* ((tags (plist-get args :tags))
                 (body (plist-get args :body))
                 (id (format "%08d-0000-0000-0000-%012d"
                             (cl-incf claude-orgmode-test--note-counter)
                             claude-orgmode-test--note-counter))
                 (path (expand-file-name (format "%s.org" id)
                                         claude-orgmode-test-directory))
                 (note (list :id id :title title :path path
                             :tags tags :aliases nil :level 0)))
            (make-directory (file-name-directory path) t)
            (with-temp-file path
              (insert (format ":PROPERTIES:\n:ID:       %s\n:END:\n" id))
              (insert (format "#+title: %s\n" title))
              (when tags
                (insert (format "#+filetags: :%s:\n"
                                (mapconcat #'identity tags ":"))))
              (when (and body (not (string-empty-p body)))
                (insert "\n" body "\n")))
            (puthash id note claude-orgmode-test--note-store)
            note))))

(defun claude-orgmode-test--rewrite-filetags (note)
  "Rewrite the #+filetags: line of NOTE's file from its stored :tags."
  (let ((path (plist-get note :path))
        (tags (plist-get note :tags)))
    (when (and path (file-exists-p path))
      (with-temp-buffer
        (insert-file-contents path)
        (goto-char (point-min))
        (if (re-search-forward "^#\\+filetags:.*$" nil t)
            (if tags
                (replace-match (format "#+filetags: :%s:"
                                       (mapconcat #'identity tags ":")))
              (delete-region (line-beginning-position)
                             (min (point-max) (1+ (line-end-position)))))
          ;; No existing filetags line: insert after the #+title: line.
          (when (and tags (re-search-forward "^#\\+title:.*$" nil t))
            (end-of-line)
            (insert (format "\n#+filetags: :%s:"
                            (mapconcat #'identity tags ":")))))
        (write-region (point-min) (point-max) path nil 'silent)))))

;;; Setup / teardown

(defun claude-orgmode-test--setup ()
  "Set up the mocked vulpea backend and a fresh temp note directory."
  (setq claude-orgmode-test-directory (make-temp-file "claude-orgmode-test-" t))
  (setq claude-orgmode-test--note-store (make-hash-table :test 'equal))
  (setq claude-orgmode-test--note-counter 0)
  (setq vulpea-db-sync-directories (list claude-orgmode-test-directory))
  (claude-orgmode-test--install-mocks)
  (setq claude-orgmode--backend 'vulpea))

(defun claude-orgmode-test--teardown ()
  "Tear down the mocked backend, clear the store, delete temp files."
  (setq claude-orgmode--backend nil)
  (setq claude-orgmode-test--note-store nil)
  (setq claude-orgmode-test--note-counter 0)
  ;; Drop the global directory binding so it does not leak into specs that
  ;; expect it unbound or bind it themselves.
  (when (boundp 'vulpea-db-sync-directories)
    (makunbound 'vulpea-db-sync-directories))
  ;; Kill any live buffers visiting files in the test directory so deleting it
  ;; does not leave dangling buffers that error on re-save.
  (when claude-orgmode-test-directory
    (let ((dir (file-name-as-directory
                (expand-file-name claude-orgmode-test-directory))))
      (dolist (buf (buffer-list))
        (let ((file (buffer-file-name buf)))
          (when (and file (string-prefix-p dir (expand-file-name file)))
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf))))))
  (when (and claude-orgmode-test-directory
             (file-exists-p claude-orgmode-test-directory))
    (delete-directory claude-orgmode-test-directory t))
  (setq claude-orgmode-test-directory nil))

;;; Note-store helpers

(defun claude-orgmode-test--register-note (id path &optional level title tags)
  "Register a note in the mock store so backend lookups by ID resolve.
ID is the node ID string (must match an :ID: written into PATH).
PATH is the real `.org' file containing that ID.
LEVEL is the node level (0 = file-level, default 0).
TITLE and TAGS are optional metadata.

Section-editing tests write a real `.org' file containing several IDs, then
register each ID they operate on.  Production code navigates to the heading by
ID within the file itself, so the registered note only needs an accurate :path
and :level."
  (puthash id
           (list :id id :title (or title id) :path path
                 :tags tags :aliases nil :level (or level 0))
           claude-orgmode-test--note-store)
  id)

;;; Assertion helpers

(defun claude-orgmode-test--count-nodes ()
  "Return the number of nodes in the mock store."
  (length (claude-orgmode--backend-node-list)))

(defun claude-orgmode-test--get-note-content (file-path)
  "Get the content of the note at FILE-PATH."
  (with-temp-buffer
    (insert-file-contents file-path)
    (buffer-string)))

(defun claude-orgmode-test--node-exists-p (title)
  "Check if a node with TITLE exists."
  (not (null (claude-orgmode--backend-node-from-title title))))

(provide 'test-helper)
;;; test-helper.el ends here
