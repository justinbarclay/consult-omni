;;; consult-omni-gptel.el --- Consulting gptel -*- lexical-binding: t -*-

;; Copyright (C) 2024 Armin Darvish

;; Author: Armin Darvish
;; Maintainer: Armin Darvish
;; Created: 2024
;; Version: 0.3
;; Package-Requires: (
;;         (emacs "29.4")
;;         (consult "2.0")
;;         (gptel "0.7.0")
;;         (consult-omni "0.3"))
;;
;; Homepage: https://github.com/armindarvish/consult-omni
;; Keywords: convenience

;;; Commentary:
;; consult-omni-gptel enables searching LLMS in consult-omni using gptel.
;; It provides commands to get gptel results directly in the minibuffer.
;;
;; For more info on gptel see:
;; URL `https://github.com/karthink/gptel'

;;; Code:

(require 'gptel)
(require 'consult-omni)

;;; User Options (a.k.a. Custom Variables)

(defcustom consult-omni-gptel-backend (or gptel-backend gptel--openai)
  "LLM backend to use in consult-omni-gptel.

By default inherits from `gptel-backend'.
See `gptel-backend' for more info."
  :group 'consult-omni
  :type `(choice
          (const :tag "ChatGPT" ,gptel--openai)
          (restricted-sexp :match-alternatives (gptel-backend-p 'nil)
                           :tag "Other backend")))

(defcustom consult-omni-gptel-model (or gptel-model "gpt-3.5-turbo")
  "GPT Model for use in consult-omni-gptel.

By default inherits from `gptel-model'.
See `gptel-model' for more info."
  :group 'consult-omni
  :type '(choice
          (string :tag "Specify model name")
          (const :tag "GPT 3.5 turbo" "gpt-3.5-turbo")
          (const :tag "GPT 3.5 turbo 16k" "gpt-3.5-turbo-16k")
          (const :tag "GPT 4" "gpt-4")
          (const :tag "GPT 4 turbo (preview)" "gpt-4-turbo-preview")
          (const :tag "GPT 4 32k" "gpt-4-32k")
          (const :tag "GPT 4 1106 (preview)" "gpt-4-1106-preview")))

(defcustom consult-omni-gptel-buffer-name  "*consult-omni-gptel*"
  "Name for consult-omni-gptel buffer."
  :group 'consult-omni
  :type '(choice (string :tag "A string for buffer name")
                 (function :tag "A custom function taking prompt (and other args) as input and returning buffer name string")))

(defcustom consult-omni-gptel-cand-title #'consult-omni--gptel-make-title-short-answer
  "What to show as the title in in the minibuffer?"
  :group 'consult-omni
  :type '(choice (function :tag "(Default) Get a quick short answer (Sends the prompt to LLM) and shows a short response.)" #'consult-omni--gptel-make-title-short-answer)
                 (function :tag "Placeholder string with prompt (Does not send prompt to LLM until the candidate is selected.)" #'consult-omni--gptel-make-title-placeholder)
                 (function :tag "A custom function taking input (and other args) as input and returning a string")
                 (string :tag "A custom fixed string")))

(defcustom consult-omni-gptel-short-answer-wordcount 10
  "Number of words to use in a short answer."
  :group 'consult-omni
  :type 'integer)

(cl-defun consult-omni--gptel-format-candidate (&rest args &key source query title model backend stream face &allow-other-keys)
  "Return a formatted string for gptel's candidates with ARGS.

Description of Arguments:

  SOURCE   the name to use (e.g. “gptel”)
  QUERY    query input from the user
           the search results of QUERY on the SOURCE website
  TITLE    the string of the candidate.
  MODEL    the model to use for gptel.  See `gptel-mode' for details.
  BACKEND  the backend to use for gptel.  See `gptel-backend' for details.
  STREAM   boolean to determine whether to use strem or not.
           see`gptel-stream' for details.
  FACE     the face to apply to TITLE"
  (let* ((frame-width-percent (floor (* (frame-width) 0.1)))
         (source (and (stringp source) (propertize source 'face 'consult-omni-source-type-face)))
         (match-str (and (stringp query) (not (equal query ".*")) (consult--split-escaped query)))
         (backend (and (stringp backend) (propertize backend 'face 'consult-omni-domain-face)))
         (model (and (stringp model) (propertize model 'face 'consult-omni-path-face)))
         (stream (and stream (propertize "~stream~" 'face 'consult-omni-snippet-face)))
         (face (or (consult-omni--get-source-prop source :face) face 'consult-omni-default-face))
         (title-str (and title (stringp title) (propertize title 'face face)))
         (title-str (consult-omni--set-string-width title-str (* 5 frame-width-percent)))
         (str (concat title-str
                      (when backend (concat "\t" backend))
                      (when model (concat ":" model))
                      (when stream (concat "\s" stream "\s")))))
    (if consult-omni-highlight-matches-in-minibuffer
        (cond
         ((listp match-str)
          (mapc (lambda (match) (setq str (consult-omni--highlight-match match str t))) match-str))
         ((stringp match-str)
          (setq str (consult-omni--highlight-match match-str str t)))))
    str))

(defun consult-omni--gptel-buffer-name (&optional query &rest args)
  "Return a string for `consult-omni-gptel' buffer name with QUERY and ARGS.

QUERY is a string, the prompt to send to gptel."
  (cond
   ((functionp consult-omni-gptel-buffer-name)
    (funcall consult-omni-gptel-buffer-name query args))
   ((stringp consult-omni-gptel-buffer-name)
    consult-omni-gptel-buffer-name)
   (t "*consult-omni-gptel*")))

(cl-defun consult-omni--gptel-response-preview (query &rest args &key backend model stream &allow-other-keys)
  "Return a `gptel' buffer for QUERY and ARGS.

Description of Arguments:
  QUERY  a string; the prompt that is sent to gptel
  BACKEND a symbol; the backend used for gptel (see `gptel-backend')
  MODEL  a string; the model to use for gptel (see `gptel-model')
  STREAM a boolean; when non-nil, the response is streamed"
  (save-excursion
    (with-current-buffer (gptel (consult-omni--gptel-buffer-name query args) nil nil nil)
      (let* ((query-sent)
             (backend (and backend (car (seq-filter (lambda (item) (when (string-match (format "%s" backend) item) item)) (mapcar #'car gptel--known-backends)))))
             (backend (or backend (gptel-backend-name consult-omni-gptel-backend)))
             (backend (cdr (assoc (format "%s" backend) gptel--known-backends)))
             (model (or (and model (format "%s" model))
                        (and backend (car (cl-struct-slot-value (type-of backend) 'models backend)))
                        consult-omni-gptel-model))
             (stream (if stream t nil)))
        (setq-local gptel-backend backend)
        (setq-local gptel-model model)
        (setq-local gptel-stream stream)
        (erase-buffer)
        (insert (gptel-prompt-prefix-string))
        (insert (format "%s" query))
        (unless query-sent
          (erase-buffer)
          (insert (gptel-prompt-prefix-string) query)
          (setq query-sent t)
          (gptel-send)))
      (current-buffer))))

(defun consult-omni--gptel-preview (cand)
  "Show a preview buffer of CAND from `consult-omni-gptel'.

The preview buffer is from `consult-omni--gptel-response-preview'."
  (if (listp cand) (setq cand (or (car-safe cand) cand)))
  (let*  ((query (get-text-property 0 :query cand))
          (backend (get-text-property 0 :backend cand))
          (model (get-text-property 0 :model cand))
          (stream (get-text-property 0 :stream cand))
          (buff (consult-omni--gptel-response-preview query :model model :backend backend :stream stream)))
    (if buff
        (funcall (consult--buffer-preview) 'preview
                 buff))))

(cl-defun consult-omni--gptel-make-title-placeholder (input &rest args &key callback &allow-other-keys)
  "Make a placeholder for sending INPUT to gptel with ARGS.

This makes a placeholder string “ask gptel: %s” %s=INPUT with
metadata so it can be send to `gptel'.

CALLBACK is a function used internally to update the list of candidates in
the minibuffer asynchronously.  It is called with a list of strings, which
are new annotated candidates \(e.g. as they arrive from an asynchronous
process\) to be added to the minibuffer completion cnadidates.  See the
section on REQUEST in documentation for `consult-omni-define-source' as
well as the function
`consult-omni--multi-update-dynamic-candidates' for how CALLBACK is used."
  (pcase-let* ((`(,query . ,opts) (consult-omni--split-command input (if callback (seq-difference args (list :callback callback)) args)))
               (opts (car-safe opts))
               (source "gptel")
               (backend (and (plist-member opts :backend) (format "%s" (plist-get opts :backend))))
               (backend (and backend (car (seq-filter (lambda (item) (when (string-match (format "%s" backend) item) item)) (mapcar #'car gptel--known-backends)))))
               (backend (or backend (gptel-backend-name consult-omni-gptel-backend)))
               (backend-struct  (cdr (assoc (format "%s" backend) gptel--known-backends)))
               (model (and (plist-member opts :model) (format "%s" (plist-get opts :model))))
               (model (or (and model backend-struct (member model (cl-struct-slot-value (type-of backend-struct) 'models backend-struct)) model)
                          (and backend-struct (car (cl-struct-slot-value (type-of backend-struct) 'models backend-struct)))))
               (stream (or (and (plist-member opts :stream) (plist-get opts :stream)) gptel-stream))
               (placeholder (format "ask gptel: %s" (if query (string-trim-right query) "")))
               (decorated (consult-omni--gptel-format-candidate :source source :query query :title placeholder :model model :backend backend :stream stream))
               (annotated-results
                (propertize decorated
                            :source source
                            :title query
                            :url nil
                            :query query
                            :model model
                            :stream stream
                            :backend backend)))
    (when (and annotated-results (functionp callback))
      (funcall callback (list annotated-results)))
    (list annotated-results)))

(cl-defun consult-omni--gptel-make-title-short-answer (input &rest args &key callback &allow-other-keys)
  "Get a short preview answer from gptel for INPUT with ARGS.

CALLBACK is a function used internally to update the list of candidates in
the minibuffer asynchronously.  It is called with a list of strings, which
are new annotated candidates \(e.g. as they arrive from an asynchronous
process\) to be added to the minibuffer completion cnadidates.  See the
section on REQUEST in documentation for `consult-omni-define-source' as
well as the function
`consult-omni--multi-update-dynamic-candidates' for how CALLBACK is used."
  (pcase-let* ((`(,query . ,opts) (consult-omni--split-command input (if callback (seq-difference args (list :callback callback)) args)))
               (opts (car-safe opts))
               (source "gptel")
               (backend (and (plist-member opts :backend) (format "%s" (plist-get opts :backend))))
               (backend (and backend (car (seq-filter (lambda (item) (when (string-match (format "%s" backend) item) item)) (mapcar #'car gptel--known-backends)))))
               (backend (or backend (gptel-backend-name consult-omni-gptel-backend)))
               (backend-struct (cdr (assoc (format "%s" backend) gptel--known-backends)))
               (model (and (plist-member opts :model) (format "%s" (plist-get opts :model))))
               (model (or (and model backend-struct (member model (cl-struct-slot-value (type-of backend-struct) 'models backend-struct)) model)
                          (and backend-struct (car (cl-struct-slot-value (type-of backend-struct) 'models backend-struct)))
                          consult-omni-gptel-model))
               (stream (or (and (plist-member opts :stream) (plist-get opts :stream)) gptel-stream))
               (gptel-backend backend-struct)
               (gptel-model model)
               (gptel-stream (if stream t nil))
               (output))
    (gptel-request query
      :system (format "Respond in %s words or less." consult-omni-gptel-short-answer-wordcount)
      :callback
      (lambda (response _)
        (when response
          (let* ((decorated
                  (consult-omni--gptel-format-candidate :source source :query query :title (string-trim-right response) :model model :backend backend :stream stream))
                 (annotated-result (propertize decorated
                                               :title response
                                               :source "gptel"
                                               :url nil
                                               :query query
                                               :model model
                                               :stream stream
                                               :backend backend)))
            (when annotated-result
              (when callback
                (funcall callback (list annotated-result)))
              (setq output (list annotated-result)))))))
    output))

(defun consult-omni--gptel-valid-input-p (&optional input)
  "Check if INPUT has a space in it."
  (cond
   ((stringp input)
    (if (string-match-p "\s" input)
        input
      nil))
   (t input)))

(cl-defun consult-omni--gptel-fetch-results (input &rest args &key callback &allow-other-keys)
  "Fetch chat response for INPUT from gptel with ARGS.

CALLBACK is a function used internally to update the list of candidates in
the minibuffer asynchronously.  It is called with a list of strings, which
are new annotated candidates \(e.g. as they arrive from an asynchronous
process\) to be added to the minibuffer completion cnadidates.  See the
section on REQUEST in documentation for `consult-omni-define-source' as
well as the function
`consult-omni--multi-update-dynamic-candidates' for how CALLBACK is used."
  (unless (featurep 'gptel)
    (error "Consult-omni: gptel is not available.  Make sure to install and load `gptel'"))
  (let ((results))
    (cond
     ((stringp consult-omni-gptel-cand-title) (setq results (list consult-omni-gptel-cand-title)))
     ((functionp consult-omni-gptel-cand-title)
      (setq results (apply consult-omni-gptel-cand-title input :callback callback args))))
    results))

;; Define the gptel source
(consult-omni-define-source "gptel"
                            :narrow-char ?a
                            :type 'dynamic
                            :require-match t
                            :face 'consult-omni-ai-title-face
                            :request #'consult-omni--gptel-fetch-results
                            :min-input 5
                            ;:valid-input #'consult-omni--gptel-valid-input-p
                            :on-preview #'consult-omni--gptel-preview
                            :on-return #'identity
                            :on-callback #'consult-omni--gptel-preview
                            :preview-key consult-omni-preview-key
                            :search-hist 'consult-omni--search-history
                            :select-hist 'consult-omni--selection-history
                            :enabled (lambda () (fboundp 'gptel))
                            :group #'consult-omni--group-function
                            :sort t
                            :interactive consult-omni-intereactive-commands-type
                            :annotate nil)

;;; provide `consult-omni-gptel' module

(provide 'consult-omni-gptel)

(add-to-list 'consult-omni-sources-modules-to-load 'consult-omni-gptel)
;;; consult-omni-gptel.el ends here
