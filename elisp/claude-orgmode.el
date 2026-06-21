;;; claude-orgmode.el --- Claude Code plugin for org-mode note management -*- lexical-binding: t; -*-

;; Copyright (C) 2025-2026

;; Author: Tahir Butt
;; Version: 4.0.0
;; Package-Requires: ((emacs "27.2"))
;; Keywords: outlines convenience
;; URL: https://github.com/majorgreys/claude-orgmode

;;; Commentary:

;; This package provides functions for programmatic org-mode note management
;; via emacsclient, backed by the vulpea backend.
;;
;; Key features:
;; - Create notes with automatic template detection
;; - Search and query notes
;; - Manage backlinks and connections
;; - Tag management
;; - File attachments via org-attach
;; - Diagnostic tools
;;
;; Usage:
;; Add to your Emacs configuration:
;;   (require 'claude-orgmode)
;;
;; Then use emacsclient to call functions:
;;   emacsclient --eval "(claude-orgmode-create-note \"Title\" :tags '(\"tag\"))"

;;; Code:

;; Backend (vulpea) - resolved lazily on first use
(require 'claude-orgmode-backend)

;; Load all modules
(require 'claude-orgmode-core)
(require 'claude-orgmode-create)
(require 'claude-orgmode-search)
(require 'claude-orgmode-links)
(require 'claude-orgmode-tags)
(require 'claude-orgmode-attach)
(require 'claude-orgmode-section)
(require 'claude-orgmode-utils)
(require 'claude-orgmode-doctor)

(provide 'claude-orgmode)
;;; claude-orgmode.el ends here
