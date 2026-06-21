;;; claude-orgmode-create.el --- Note creation functions -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Tahir Butt
;; Keywords: outlines convenience

;;; Commentary:
;; Functions for creating notes programmatically (vulpea backend).

;;; Code:

(require 'cl-lib)
(require 'claude-orgmode-core)
(require 'claude-orgmode-backend)

;;;###autoload
(cl-defun claude-orgmode-create-note (title &key tags content content-file keep-file)
  "Create a vulpea note with TITLE, optional TAGS and CONTENT.
TAGS is a list of strings (hyphens are sanitized to underscores).
CONTENT can be a string, or CONTENT-FILE a path (which takes priority
and is deleted after use unless KEEP-FILE is non-nil and it looks like
a temp file).
Return the file path of the created note."
  (let* ((actual-content (cond
                          (content-file (claude-orgmode--read-content-file content-file))
                          (content content)
                          (t nil)))
         (clean-tags (mapcar #'claude-orgmode--sanitize-tag tags))
         (note (vulpea-create title nil :tags clean-tags :body (or actual-content ""))))
    (when (and content-file (not keep-file) (file-exists-p content-file)
               (claude-orgmode--looks-like-temp-file content-file))
      (ignore-errors (delete-file content-file)))
    (vulpea-note-path note)))

;;;###autoload
(defun claude-orgmode-create-note-with-content (title content &optional tags)
  "Create a new vulpea note with TITLE, CONTENT and optional TAGS.
This is an alias for claude-orgmode-create-note with different arg order.
Return the file path of the created note."
  (claude-orgmode-create-note title :content content :tags tags))

(provide 'claude-orgmode-create)
;;; claude-orgmode-create.el ends here
