;; -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'json)
(require 'subr-x)

;;; ----  Project / scheme detection  ----

(defun agent-skill-xcode--project ()
  "Return a list (KIND PATH) for the Xcode project under `default-directory'.
KIND is `workspace' or `project'. Workspaces are preferred when both exist."
  (let ((ws (car (directory-files default-directory t "\\.xcworkspace\\'" t)))
        (proj (car (directory-files default-directory t "\\.xcodeproj\\'" t))))
    (cond
     (ws (list 'workspace ws))
     (proj (list 'project proj))
     (t (user-error "No .xcworkspace or .xcodeproj in %s" default-directory)))))

(defun agent-skill-xcode--target-args (kind path)
  "xcodebuild flag pair for KIND/PATH, suitable for splicing into a shell command."
  (format "%s %s"
          (if (eq kind 'workspace) "-workspace" "-project")
          (shell-quote-argument path)))

(defun agent-skill-xcode--scheme (kind path)
  "Pick a scheme via `xcodebuild -list -json'.
Prefer the scheme matching the project basename; else the first non-test scheme."
  (let* ((cmd (format "xcodebuild %s -list -json 2>/dev/null"
                      (agent-skill-xcode--target-args kind path)))
         (data (with-temp-buffer
                 (call-process-shell-command cmd nil (current-buffer))
                 (goto-char (point-min))
                 (ignore-errors
                   (json-parse-buffer :object-type 'alist :array-type 'list))))
         (schemes (or (alist-get 'schemes (alist-get 'workspace data))
                      (alist-get 'schemes (alist-get 'project data))))
         (basename (file-name-base path)))
    (unless schemes
      (user-error "No schemes found in %s" path))
    (or (cl-find basename schemes :test #'string=)
        (cl-find-if-not (lambda (s) (string-match-p "Test\\|UITest" s)) schemes)
        (car schemes))))

;;; ----  Output helpers  ----

(defun agent-skill-xcode--tail (s n)
  (let ((lines (split-string s "\n" t)))
    (mapconcat #'identity (last lines n) "\n")))

;;; ----  Build  ----

(defun agent-skill-xcode--build (kind path scheme destination)
  "Run `xcodebuild build'. Return a plist (:exit :tail :scheme)."
  (let ((cmd (format "xcodebuild %s -scheme %s -destination %s build 2>&1"
                     (agent-skill-xcode--target-args kind path)
                     (shell-quote-argument scheme)
                     (shell-quote-argument destination))))
    (with-temp-buffer
      (let ((exit (call-process-shell-command cmd nil (current-buffer))))
        (list :exit exit
              :scheme scheme
              :destination destination
              :tail (agent-skill-xcode--tail (buffer-string) 40))))))

(defun agent-skill-xcode--summarize-build (result)
  (if (eq 0 (plist-get result :exit))
      (format "Build succeeded: scheme=%s destination=%s"
              (plist-get result :scheme)
              (plist-get result :destination))
    (format "Build FAILED: scheme=%s destination=%s\n\n--- last 40 lines ---\n%s"
            (plist-get result :scheme)
            (plist-get result :destination)
            (plist-get result :tail))))

;;; ----  Build entry points  ----

(cl-defun agent-skill-xcode-build-simulator (&key project-dir)
  "Build for iOS Simulator (generic destination). Returns a status string."
  (let ((default-directory (or project-dir default-directory)))
    (cl-destructuring-bind (kind path) (agent-skill-xcode--project)
      (let ((scheme (agent-skill-xcode--scheme kind path)))
        (agent-skill-xcode--summarize-build
         (agent-skill-xcode--build kind path scheme
                                   "generic/platform=iOS Simulator"))))))

(cl-defun agent-skill-xcode-build-device (&key project-dir)
  "Build for an iOS device (generic destination). Returns a status string.
Requires a configured signing team in the project; otherwise xcodebuild will
fail with a code-signing error."
  (let ((default-directory (or project-dir default-directory)))
    (cl-destructuring-bind (kind path) (agent-skill-xcode--project)
      (let ((scheme (agent-skill-xcode--scheme kind path)))
        (agent-skill-xcode--summarize-build
         (agent-skill-xcode--build kind path scheme
                                   "generic/platform=iOS"))))))

;;; ----  Simulator selection  ----

(defun agent-skill-xcode--booted-simulator ()
  "Return the UDID of the first booted iOS simulator, or nil."
  (let ((data (with-temp-buffer
                (call-process-shell-command
                 "xcrun simctl list devices booted -j" nil (current-buffer))
                (goto-char (point-min))
                (ignore-errors
                  (json-parse-buffer :object-type 'alist :array-type 'list)))))
    (when data
      (catch 'found
        (dolist (runtime (alist-get 'devices data))
          (when (string-match-p "iOS" (symbol-name (car runtime)))
            (dolist (dev (cdr runtime))
              (when (string= "Booted" (alist-get 'state dev))
                (throw 'found (alist-get 'udid dev))))))))))

(defun agent-skill-xcode--latest-iphone-simulator ()
  "Pick the latest available iPhone simulator UDID across iOS runtimes."
  (let* ((data (with-temp-buffer
                 (call-process-shell-command
                  "xcrun simctl list devices available -j" nil (current-buffer))
                 (goto-char (point-min))
                 (json-parse-buffer :object-type 'alist :array-type 'list)))
         (runtimes (sort (cl-remove-if-not
                          (lambda (r) (string-match-p "iOS" (symbol-name (car r))))
                          (alist-get 'devices data))
                         (lambda (a b)
                           (string-greaterp (symbol-name (car a))
                                            (symbol-name (car b)))))))
    (catch 'found
      (dolist (runtime runtimes)
        (dolist (dev (cdr runtime))
          (when (and (eq t (alist-get 'isAvailable dev))
                     (string-match-p "iPhone" (alist-get 'name dev)))
            (throw 'found (alist-get 'udid dev)))))
      (user-error "No available iPhone simulator found"))))

(defun agent-skill-xcode--pick-simulator ()
  "Return UDID of a usable simulator: existing booted, else latest iPhone (boot it)."
  (or (agent-skill-xcode--booted-simulator)
      (let ((udid (agent-skill-xcode--latest-iphone-simulator)))
        (call-process-shell-command (format "xcrun simctl boot %s" udid))
        (call-process-shell-command "open -a Simulator")
        udid)))

;;; ----  Device selection  ----

(defun agent-skill-xcode--connected-device ()
  "Return the UDID of the first wired-connected iOS device, or signal an error."
  (let* ((tmp (make-temp-file "agent-xcode-devices-" nil ".json"))
         (_ (call-process-shell-command
             (format "xcrun devicectl list devices -j %s 2>/dev/null"
                     (shell-quote-argument tmp))))
         (data (with-temp-buffer
                 (insert-file-contents tmp)
                 (goto-char (point-min))
                 (json-parse-buffer :object-type 'alist :array-type 'list)))
         (devices (alist-get 'devices (alist-get 'result data))))
    (catch 'found
      (dolist (dev devices)
        (let* ((conn (alist-get 'connectionProperties dev))
               (transport (alist-get 'transportType conn)))
          (when (and transport
                     (string-match-p "wired\\|localNetwork" transport))
            (throw 'found (alist-get 'identifier dev)))))
      (user-error "No connected iOS device found"))))

;;; ----  Build settings  ----

(defun agent-skill-xcode--build-settings (kind path scheme destination)
  "Return (:app PATH :bundle-id ID) for the given build."
  (let* ((cmd (format "xcodebuild %s -scheme %s -destination %s -showBuildSettings -json 2>/dev/null"
                      (agent-skill-xcode--target-args kind path)
                      (shell-quote-argument scheme)
                      (shell-quote-argument destination)))
         (data (with-temp-buffer
                 (call-process-shell-command cmd nil (current-buffer))
                 (goto-char (point-min))
                 (json-parse-buffer :object-type 'alist :array-type 'list)))
         (settings (alist-get 'buildSettings (car data))))
    (list :app (expand-file-name (alist-get 'WRAPPER_NAME settings)
                                 (alist-get 'BUILT_PRODUCTS_DIR settings))
          :bundle-id (alist-get 'PRODUCT_BUNDLE_IDENTIFIER settings))))

;;; ----  Run entry points  ----

(cl-defun agent-skill-xcode-run-simulator (&key project-dir)
  "Build, install, and launch on an iOS simulator.
If a simulator is already booted, use it; otherwise boot the latest iPhone.
Returns a status string."
  (let ((default-directory (or project-dir default-directory)))
    (cl-destructuring-bind (kind path) (agent-skill-xcode--project)
      (let* ((scheme (agent-skill-xcode--scheme kind path))
             (udid (agent-skill-xcode--pick-simulator))
             (dest (format "platform=iOS Simulator,id=%s" udid))
             (build (agent-skill-xcode--build kind path scheme dest)))
        (if (not (eq 0 (plist-get build :exit)))
            (agent-skill-xcode--summarize-build build)
          (let* ((settings (agent-skill-xcode--build-settings kind path scheme dest))
                 (app (plist-get settings :app))
                 (bundle (plist-get settings :bundle-id))
                 (install (string-trim (shell-command-to-string
                                        (format "xcrun simctl install %s %s 2>&1"
                                                udid (shell-quote-argument app)))))
                 (launch (string-trim (shell-command-to-string
                                       (format "xcrun simctl launch %s %s 2>&1"
                                               udid (shell-quote-argument bundle))))))
            (format "Launched %s on simulator %s\nApp: %s\nInstall: %s\nLaunch: %s"
                    bundle udid app
                    (if (string-empty-p install) "ok" install)
                    launch)))))))

(cl-defun agent-skill-xcode-run-device (&key project-dir)
  "Build, install, and launch on a connected iOS device.
Requires Xcode 15+ (`devicectl') and a configured signing team. Returns a
status string."
  (let ((default-directory (or project-dir default-directory)))
    (cl-destructuring-bind (kind path) (agent-skill-xcode--project)
      (let* ((udid (agent-skill-xcode--connected-device))
             (scheme (agent-skill-xcode--scheme kind path))
             (dest (format "platform=iOS,id=%s" udid))
             (build (agent-skill-xcode--build kind path scheme dest)))
        (if (not (eq 0 (plist-get build :exit)))
            (agent-skill-xcode--summarize-build build)
          (let* ((settings (agent-skill-xcode--build-settings kind path scheme dest))
                 (app (plist-get settings :app))
                 (bundle (plist-get settings :bundle-id))
                 (install (string-trim (shell-command-to-string
                                        (format "xcrun devicectl device install app --device %s %s 2>&1"
                                                udid (shell-quote-argument app)))))
                 (launch (string-trim (shell-command-to-string
                                       (format "xcrun devicectl device process launch --device %s %s 2>&1"
                                               udid (shell-quote-argument bundle))))))
            (format "Launched %s on device %s\nApp: %s\nInstall: %s\nLaunch: %s"
                    bundle udid app
                    install launch)))))))

(provide 'agent-skill-xcode)
