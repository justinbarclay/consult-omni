;;; consult-omni-org-agenda.el --- Consulting Org Agenda -*- lexical-binding: t -*-

;; Copyright (C) 2024 Armin Darvish

;; Author: Armin Darvish
;; Maintainer: Armin Darvish
;; Created: 2024
;; Version: 0.3
;; Package-Requires: (
;;         (emacs "29.4")
;;         (consult "2.0")
;;         (consult-omni "0.3"))
;;
;; Homepage: https://github.com/armindarvish/consult-omni
;; Keywords: convenience

;;; Commentary:
;; consult-omni-org-agenda enables searching `org-agenda' directly in Emacs ;; minibuffer using consult-omni.  It provides commands to search aegnda
;; items and see relevant items in the minibuffer and has support for
;; filter and narrow down based on dates or tags, etc.

;;; Code:

(require 'consult-omni)

(defcustom consult-omni-org-agenda-number-of-days-around 7
  "Number of days to use for listing agenda items around a date.

agenda items for +/- days around a given date will be listed.
See `consult-omni--org-agenda-around' for more details."
  :group 'consult-omni
  :type 'integer)


(defcustom consult-omni-org-agenda-transform-prefix "?"
  "Prefix in query to trigger transformation.

If the user input includes this prefix string, `consult-omni-org-agenda'
tries to transform the query if needed.  This is used to transform search terms
like “today”, “this week”, “around last month”, etc. to date and date ranges.
See `consult-omni--org-agenda-query-dwim-transform' for details."
  :group 'consult-omni
  :type 'string)


(defcustom consult-omni-org-agenda-timestamp-format (or (and (bound-and-true-p org-timestamp-formats) (car org-timestamp-formats)) "%Y-%m-%d %a")
  "Timestamp format for time string in `consult-omni-org-agenda'.

This string is used to format timestamps in the marginalia info.
See `org-timestamp-formats' and `org-time-stamp-format'
for org fomrating, and `format-time-string' for more details."
  :group 'consult-omni
  :type 'string)


(defcustom consult-omni-org-agenda-regexp-builder #'consult-omni--org-agenda-split-by-space
  "Function to transform query to a regexp pattern.

This funciton is called with the input query to get a
matching regexp pattern."
  :group 'consult-omni
  :type '(choice (const :tag "(Default) match any word sepearated by space" consult-omni--org-agenda-split-by-space)
                 (funciton :tag "custom function")))

(defun consult-omni--org-agenda-format-time-string (date &optional format)
  "Format DATE according to FORMAT using `format-time-string'.

If FORMAT is nil, uses `consult-omni-org-agenda-timestamp-format' as
fallback."
  (condition-case err
      (format-time-string (or format consult-omni-org-agenda-timestamp-format) date)
    (error (progn (message (error-message-string err))
                  nil))))

(defun consult-omni--org-agenda-date-range-regexp (date-strings &optional format-func)
  "Make a regexp matching DATE-STRINGS.

DATE-STRINGS a list; list of date strings.
FORMAT-FUNC  a function; function to format each date in DATE-STRINGS
             FORMAT-FUNC defaults to
             `consult-omni--org-agenda-format-time-string'."
  (let ((format-func (or format-func #'consult-omni--org-agenda-format-time-string)))
    (mapconcat (lambda (date) (if (stringp date) date (funcall format-func date))) date-strings "\\|")))

(defun consult-omni--org-agenda-relative-date (date int unit)
  "Get the date for INT*UNIT relative to DATE.

Description of Arguments:

  INT an integer; number UNITS (days, months or years)
  UNIT a constant; either :day, :month or :year."
  (if (stringp date) (setq date  (date-to-time date)))
  (setq int (or (and (numberp int) int)
                (and (stringp int) (string-to-number int))))
  (unless (member unit '(:day :month :year :week)) (setq unit (intern (concat ":" (format "%s" unit)))))
  (when (eq unit :week) (setq int (* int 7)
                              unit :day))
  (if (member unit '(:day :month :year))
      (encode-time (decoded-time-add (decode-time date) (make-decoded-time unit int)))
    (message "Cannot use %s in calculating relative date." unit)))

(defun consult-omni--org-agenda-previous-day (date)
  "Get the date for one day before DATE."
  (consult-omni--org-agenda-relative-date date -1 :day))

(defun consult-omni--org-agenda-next-day (date)
  "Get the date for the next day after DATE."
  (consult-omni--org-agenda-relative-date date 1 :day))

(defun consult-omni--org-agenda-begin-week (date)
  "Get the date of the first day of the week for DATE."
  (if (stringp date) (setq date  (date-to-time date)))
  (let ((day-of-week (decoded-time-weekday (decode-time date))))
    (consult-omni--org-agenda-relative-date date (- 0 day-of-week) :day)))

(defun consult-omni--org-agenda-begin-work-week (date)
  "Get the date of the first working day of the week for DATE."
  (consult-omni--org-agenda-next-day (consult-omni--org-agenda-begin-week date)))

(defun consult-omni--org-agenda-week-from (date)
  "Get the dates for one week starting at DATE."
  (cl-loop for d from 0 to 6
           collect (consult-omni--org-agenda-relative-date date d :day)))

(defun consult-omni--org-agenda-week-of (date)
  "Get the dates for the calendar week of DATE."
  (consult-omni--org-agenda-week-from (consult-omni--org-agenda-begin-week date)))

(defun consult-omni--org-agenda-work-week-of (date)
  "Get the dates for the working week of DATE."
  (cl-loop for d from 0 to 4
           collect (consult-omni--org-agenda-relative-date
                    (consult-omni--org-agenda-begin-work-week date) d :day)))

(defun consult-omni--org-agenda-next-week (date)
  "Get the list of dates for the calendar week after DATE."
  (consult-omni--org-agenda-week-of (consult-omni--org-agenda-relative-date date 7 :day)))

(defun consult-omni--org-agenda-next-work-week (date)
  "Get the list of dates for the working week after DATE."
  (consult-omni--org-agenda-work-week-of (consult-omni--org-agenda-relative-date date 7 :day)))

(defun consult-omni--org-agenda-previous-week (date)
  "Get the list of dates for the calendar week before DATE."
  (consult-omni--org-agenda-week-of (consult-omni--org-agenda-relative-date date -7 :day)))

(defun consult-omni--org-agenda-previous-work-week (date)
  "Get the list of dates for the working week before DATE."
  (consult-omni--org-agenda-work-week-of (consult-omni--org-agenda-relative-date date -7 :day)))

(defun consult-omni--org-agenda-next-month (date)
  "Get the year-month string for one month after the DATE."
  (consult-omni--org-agenda-relative-date date 1 :month))

(defun consult-omni--org-agenda-previous-month (date)
  "Get the year-month string for one month before the DATE."
  (consult-omni--org-agenda-relative-date date -1 :month))

(defun consult-omni--org-agenda-next-year (date)
  "Get the year-month string for one year after the DATE."
  (consult-omni--org-agenda-relative-date date 1 :year))

(defun consult-omni--org-agenda-previous-year (date)
  "Get the year-month string for one year before the DATE."
  (consult-omni--org-agenda-relative-date date -1 :year))

(defun consult-omni--org-agenda-around (date int unit)
  "Get the dates for (+/-)INT*UNIT around the DATE.

Description of Arguments:
  INT  an integer; number of days, or months or years
  UNIT a constant; either :day, :month or :year"
  (cl-loop for d from (- 0 int) to int
           collect (consult-omni--org-agenda-relative-date date d unit)))

(defun consult-omni--org-agenda-query-dwim-transform (query)
  "Transform QUERY to what the user means.

Try to guess the dates based on user input query.
For example to get the date for tommorrow, next week, ..."
  (save-match-data
    (if consult-omni-org-agenda-transform-prefix
        (cond
         ((string-prefix-p consult-omni-org-agenda-transform-prefix query)
          (setq query (s-downcase (string-remove-prefix consult-omni-org-agenda-transform-prefix query))))
         (t
          (setq query nil))))
    (if query
        (cond
         ((string-match "around \\(.*\\)" query)
          (when-let ((date (consult-omni--org-agenda-query-dwim-transform (concat consult-omni-org-agenda-transform-prefix (match-string 1 query)))))
            (consult-omni--org-agenda-date-range-regexp (consult-omni--org-agenda-around (or (car-safe date) date) consult-omni-org-agenda-number-of-days-around :day))))
         ((equal query "yesterday") (consult-omni--org-agenda-format-time-string
                                     (consult-omni--org-agenda-previous-day (current-time))))
         ((equal query "today") (consult-omni--org-agenda-format-time-string (current-time)))
         ((equal query "tomorrow") (consult-omni--org-agenda-format-time-string
                                    (consult-omni--org-agenda-next-day (current-time))))
         ((equal query "this week") (consult-omni--org-agenda-date-range-regexp
                                     (consult-omni--org-agenda-week-of (current-time))))
         ((equal query "this work week") (consult-omni--org-agenda-date-range-regexp
                                          (consult-omni--org-agenda-work-week-of (current-time))))
         ((equal query "next week") (consult-omni--org-agenda-date-range-regexp
                                     (consult-omni--org-agenda-next-week (current-time))))
         ((equal query "next work week") (consult-omni--org-agenda-date-range-regexp
                                          (consult-omni--org-agenda-next-work-week (current-time))))
         ((equal query "last week") (consult-omni--org-agenda-date-range-regexp
                                     (consult-omni--org-agenda-previous-week (current-time))))
         ((equal query "last work week") (consult-omni--org-agenda-date-range-regexp
                                          (consult-omni--org-agenda-previous-work-week (current-time))))
         ((equal query "this month") (consult-omni--org-agenda-format-time-string (current-time) "%Y-%m"))
         ((equal query "next month") (consult-omni--org-agenda-format-time-string
                                      (consult-omni--org-agenda-next-month (current-time))
                                      "%Y-%m"))
         ((equal query "last month") (consult-omni--org-agenda-format-time-string
                                      (consult-omni--org-agenda-previous-month (current-time))
                                      "%Y-%m"))
         ((equal query "this year") (consult-omni--org-agenda-format-time-string
                                     (current-time)
                                     "%Y"))
         ((equal query "next year") (consult-omni--org-agenda-format-time-string
                                     (consult-omni--org-agenda-next-year (current-time))
                                     "%Y"))
         ((equal query "last year") (consult-omni--org-agenda-format-time-string
                                     (consult-omni--org-agenda-previous-year (current-time))
                                     "%Y"))
         ((string-match "\\([0-9]+\\) \\(.+?\\)[s]? ago" query)
          (consult-omni--org-agenda-format-time-string
           (consult-omni--org-agenda-relative-date (current-time) (- 0 (string-to-number (match-string 1 query))) (match-string 2 query))))
         ((string-match "\\([0-9]+\\) \\(.+?\\)[s]? from now" query)
          (consult-omni--org-agenda-format-time-string
           (consult-omni--org-agenda-relative-date (current-time) (string-to-number (match-string 1 query)) (match-string 2 query))))
         (t query))
      nil)))

(cl-defun consult-omni--org-agenda-format-candidate (&rest args &key source query title buffer todo prio tags filepath snippet sched dead face &allow-other-keys)
  "Format a candidate for `consult-omni-org-agenda' with ARGS.

Description of Arguments:

  SOURCE   a string; the name of the source (e.g. “Org Agenda”)
  QUERY    a string; the query input from the user
  TITLE    a string; the title of the agenda item
  BUFFER   a string; name of the buffer
  TODO     a string; todo keyword of the org heading for agenda item
  PRIO     a string; priority level of the org heading for agenda item
  TAGS     a list of strings; tags of the org agenda item
  FILEPATH a string; filepath of the org agenda item
  SNIPPET  a string; a snippet/description of the agenda item
  SCHED    a string; the scheduled date of the agenda item
  DEAD     a string; the deadline date of the agenda item
  FACE     a symbol; the face to apply to TITLE"
  (let* ((frame-width-percent (floor (* (frame-width) 0.1)))
         (source (propertize source 'face 'consult-omni-source-type-face))
         (match-str (if (and (stringp query) (not (equal query ".*"))) (consult--split-escaped query) nil))
         (buffer (and buffer (propertize (format "%s" buffer) 'face 'consult-omni-domain-face)))
         (prio (and (stringp prio) (propertize (format "[#%s]" prio) 'face 'consult-omni-prompt-face)))
         (todo (or (and (stringp todo) (propertize todo 'face (or (and org-todo-keyword-faces (cdr (assoc todo org-todo-keyword-faces)))
                                                                  (and (member todo org-done-keywords) 'org-done)
                                                                  'org-todo))) ""))
         (tags (and tags (stringp tags) (propertize tags 'face 'consult-omni-keyword-face)))
         (snippet (and snippet (stringp snippet) (propertize snippet 'face 'consult-omni-snippet-face)))
         (snippet (if (stringp snippet) (consult-omni--set-string-width (replace-regexp-in-string "\n" "  " snippet) (* 2 frame-width-percent))))
         (sched (or (and sched (stringp sched) (propertize sched 'face (or 'org-agenda-date 'consult-omni-date-face))) (make-string 16 ?\s)))
         (fraction (and dead (- 1 (min (/ (float (- (org-agenda--timestamp-to-absolute dead) (org-today))) (max (org-get-wdays dead) 1)) 1.0))))
         (dead-face (and dead
                         (org-agenda-deadline-face
			  fraction)))
         (dead (or (and dead (stringp dead) (propertize dead 'face (or dead-face 'consult-omni-warning-face))) (make-string 16 ?\s)))
         (date (concat (and (stringp sched) sched) (and (stringp sched) " ") (and (stringp dead) dead)))
         (face (or (consult-omni--get-source-prop source :face) face))
         (todo-str (concat (or prio "    ") " " todo))
         (todo-str (and (stringp todo-str) (consult-omni--set-string-width todo-str 15)))
         (title (if (and face (stringp title)) (propertize title 'face face) title))
         (title-str (if (and (stringp tags) (stringp title)) (concat title " " tags) title))
         (title-str (and (stringp title-str)
                         (consult-omni--set-string-width title-str (* 4 frame-width-percent))))
         (str (concat title-str
                      (and todo-str "\t") todo-str
                      (and buffer "\s") buffer
                      (and date "\s\s") date
                      (and snippet "\s\s") snippet
                      (and source "\t") source)))
    (if consult-omni-highlight-matches-in-minibuffer
        (cond
         ((listp match-str)
          (mapc (lambda (match) (setq str (consult-omni--highlight-match match str t))) match-str))
         ((stringp match-str)
          (setq str (consult-omni--highlight-match match-str str t)))))
    str))

(defun consult-omni--org-agenda-split-by-space (query)
  "Split QUERY string by spaces."
  (string-join (split-string query "\s" t) "\\|"))

(defun consult-omni--org-agenda-items (query &optional match &rest skip)
  "Return a list of Org heading candidates thatv match the QUERY.

MATCH, is as in `org-map-entries'
SKIP, is as in `org-map-entries'

Adopted from `consult-org--headings'."
  (let (buffer
        (source "Org Agenda"))
    (apply
     #'org-map-entries
     (lambda ()
       ;; Reset the cache when the buffer changes, since `org-get-outline-path' uses the cache
       (unless (eq buffer (buffer-name))
         (setq buffer (buffer-name)
               org-outline-path-cache nil))
       (pcase-let* ((`(_ ,level ,todo ,prio ,_hl ,tags) (org-heading-components))
                    (filename (buffer-file-name))
                    (filepath (file-truename filename))
                    (tags (if org-use-tag-inheritance
                              (when-let ((tags (org-get-tags)))
                                (concat ":" (string-join tags ":") ":"))
                            tags))
                    (title (org-format-outline-path
                            (org-get-outline-path 'with-self 'use-cache)
                            most-positive-fixnum))
                    (prio (and (characterp prio) (char-to-string prio)))
                    (marker (point-marker))
                    (props (org-entry-properties))
                    (sched (cdr (assoc "TIMESTAMP" props)))
                    (dead (cdr (assoc "DEADLINE" props)))
                    (snippet nil)
                    (transform (or (consult-omni--org-agenda-query-dwim-transform query) query)))
         (if (string-match-p (or transform (funcall consult-omni-org-agenda-regexp-builder query)) (concat todo " " prio " " _hl " " sched " " dead " " tags))
             (propertize (consult-omni--org-agenda-format-candidate :source source :query (or transform query) :title title :buffer buffer :todo todo :prio prio :tags tags :filepath filepath :snippet snippet :sched sched :dead dead) :source source :title title :query query :url nil :search-url nil :tags tags :filepath filepath :marker marker))))
     match 'agenda skip)))

(defun consult-omni--org-agenda-preview (cand)
  "Preview function for CAND from `consult-omni-org-agenda'."
  (if-let ((marker (get-text-property 0 :marker cand)))
      (consult--jump marker)))

(defun consult-omni--org-agenda-callback (cand)
  "Callback function for CAND from `consult-omni-org-agenda'."
  (if-let ((marker (get-text-property 0 :marker cand)))
      (consult--jump marker)))

(defun consult-omni--org-agenda-new (cand)
  "Callback function for new CAND from `consult-omni-org-agenda'."
  (let ((title (substring-no-properties cand))
        (old-marker org-capture-last-stored-marker))
    (org-capture-string title)
    (consult-omni-propertize-by-plist title `(:title ,title :source "Org Agenda" :url nil :search-url nil :query ,title :sched nil :dead nil :tags nil :filepath ,(cadr (org-capture-get :target)) :marker ,(unless (equal old-marker org-capture-last-stored-marker) org-capture-last-stored-marker)) 0 1)))

(cl-defun consult-omni--org-agenda-fetch-results (input &rest args &key callback &allow-other-keys)
  "Fetch `org-agenda' items matching INPUT and ARGS.

CALLBACK is a function used internally to update the list of candidates in
the minibuffer asynchronously.  It is called with a list of strings, which
are new annotated candidates \(e.g. as they arrive from an asynchronous
process\) to be added to the minibuffer completion cnadidates.  See the
section on REQUEST in documentation for `consult-omni-define-source' as
well as the function
`consult-omni--multi-update-dynamic-candidates' for how CALLBACK is used."
  (pcase-let* ((`(,query . ,opts) (consult-omni--split-command input (seq-difference args (list :callback callback))))
               (opts (car-safe opts))
               (match (or (and (plist-member opts :match) (plist-get opts :match))
                          (and (plist-member opts :filter) (plist-get opts :filter))))
               (annotated-results (delq nil (consult-omni--org-agenda-items query match))))
    (when annotated-results
      (when (functionp callback)
        (funcall callback annotated-results))
      annotated-results)))

;; Define the Org Agenda source
(consult-omni-define-source "Org Agenda"
                            :narrow-char ?o
                            :category 'org-heading
                            :type 'dynamic
                            :require-match nil
                            :request #'consult-omni--org-agenda-fetch-results
                            :on-preview #'consult-omni--org-agenda-preview
                            :on-return #'identity
                            :on-callback #'consult-omni--org-agenda-callback
                            :on-new #'consult-omni--org-agenda-new
                            :preview-key consult-omni-preview-key
                            :search-hist 'consult-omni--search-history
                            :select-hist 'consult-omni--selection-history
                            :enabled (lambda () (bound-and-true-p org-agenda-files))
                            :group #'consult-omni--group-function
                            :sort t
                            :interactive consult-omni-intereactive-commands-type)

;;; provide `consult-omni-org-agenda' module

(provide 'consult-omni-org-agenda)

(add-to-list 'consult-omni-sources-modules-to-load 'consult-omni-org-agenda)
;;; consult-omni-org-agenda.el ends here
