;;; claude-orgmode-backend.el --- Backend abstraction for vulpea -*- lexical-binding: t; -*-

;; Copyright (C) 2025-2026

;; Author: Tahir Butt
;; Keywords: outlines convenience

;;; Commentary:
;; Backend abstraction layer targeting vulpea.  Vulpea is the only
;; supported backend (it is built on top of org-roam, which is loaded
;; as a transitive dependency).  Backend resolution is lazy and cached.

;;; Code:

(require 'cl-lib)

(defvar claude-orgmode--backend nil
  "Cached backend type.  Always `vulpea' once resolved, or nil if not yet detected.")

(defun claude-orgmode--detect-backend ()
  "Return the active backend.  Vulpea is the only supported backend.
Signals an error if vulpea is not available."
  (or claude-orgmode--backend
      (setq claude-orgmode--backend
            (if (or (featurep 'vulpea) (require 'vulpea nil 'noerror))
                'vulpea
              (error "vulpea is not available")))))

(defun claude-orgmode--backend-vulpea-p ()
  "Return non-nil if the active backend is vulpea."
  (eq (claude-orgmode--detect-backend) 'vulpea))

;; Each `claude-orgmode--backend-*' function below opens with a bare
;; (claude-orgmode--detect-backend) call.  It is a fail-fast guard: it
;; signals a clear "vulpea is not available" error (and caches the
;; backend) before any vulpea-* API call runs.  It is not a no-op.

;;; Directory

(defun claude-orgmode--backend-directory ()
  "Return the notes directory for the active backend."
  (claude-orgmode--detect-backend)
  (car (if (boundp 'vulpea-db-sync-directories)
           vulpea-db-sync-directories
         (list org-directory))))

;;; Database sync

(defun claude-orgmode--backend-db-sync ()
  "Sync the database for the active backend."
  (claude-orgmode--detect-backend)
  (vulpea-db-sync-full-scan))

;;; Node/note list

(defun claude-orgmode--backend-node-list ()
  "Return all notes as a list.
Each element is a vulpea-note object."
  (claude-orgmode--detect-backend)
  (vulpea-db-query))

;;; Accessors — unified interface for note properties

(defun claude-orgmode--backend-node-id (node)
  "Return the ID of NODE."
  (claude-orgmode--detect-backend)
  (vulpea-note-id node))

(defun claude-orgmode--backend-node-title (node)
  "Return the title of NODE."
  (claude-orgmode--detect-backend)
  (vulpea-note-title node))

(defun claude-orgmode--backend-node-file (node)
  "Return the file path of NODE."
  (claude-orgmode--detect-backend)
  (vulpea-note-path node))

(defun claude-orgmode--backend-node-tags (node)
  "Return the tags of NODE as a list of strings."
  (claude-orgmode--detect-backend)
  (vulpea-note-tags node))

(defun claude-orgmode--backend-node-aliases (node)
  "Return the aliases of NODE as a list of strings."
  (claude-orgmode--detect-backend)
  (vulpea-note-aliases node))

(defun claude-orgmode--backend-node-level (node)
  "Return the heading level of NODE (0 = file-level)."
  (claude-orgmode--detect-backend)
  (vulpea-note-level node))

;;; Lookup

(defun claude-orgmode--backend-node-from-id (id)
  "Get a note by ID.  Return nil if not found."
  (claude-orgmode--detect-backend)
  (vulpea-db-get-by-id id))

(defun claude-orgmode--backend-node-from-title (title)
  "Get a note by exact TITLE or alias.  Return nil if not found."
  (claude-orgmode--detect-backend)
  (car (vulpea-db-search-by-title title)))

;;; Backlinks

(defun claude-orgmode--backend-get-backlinks (node)
  "Return backlink source notes for NODE.
Returns a list of vulpea-note objects."
  (claude-orgmode--detect-backend)
  (let ((links (vulpea-db-query-links-to (vulpea-note-id node))))
    (mapcar (lambda (link)
              (vulpea-db-get-by-id (plist-get link :source)))
            links)))

;;; Tags

(defun claude-orgmode--backend-add-tag (node tag)
  "Add TAG to NODE."
  (claude-orgmode--detect-backend)
  (vulpea-tags-add node tag))

(defun claude-orgmode--backend-remove-tag (node tag)
  "Remove TAG from NODE."
  (claude-orgmode--detect-backend)
  (vulpea-tags-remove node tag))

;;; Note creation

(cl-defun claude-orgmode--backend-create-note (title &key tags content)
  "Create a new note with TITLE, optional TAGS and CONTENT.
Returns the file path of the created note."
  (claude-orgmode--detect-backend)
  (let ((note (vulpea-create title nil
                             :tags tags
                             :body (or content ""))))
    (vulpea-note-path note)))

;;; Backend info (for diagnostics)

(defun claude-orgmode--backend-info ()
  "Return a plist describing the active backend."
  (claude-orgmode--detect-backend)
  (list :backend 'vulpea
        :directory (claude-orgmode--backend-directory)
        :database (if (boundp 'vulpea-db-location)
                      vulpea-db-location
                    "default")
        :node-count (length (vulpea-db-query))))

(provide 'claude-orgmode-backend)
;;; claude-orgmode-backend.el ends here
