;;; consult-omni-bing.el --- Consulting Bing -*- lexical-binding: t -*-

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
;; consult-omni-bing provides commands for searching bing in Emacs using ;; consult-omni.


;;; Code:
(require 'consult-omni)

;;; User Options (a.k.a. Custom Variables)

(defcustom consult-omni-bing-search-api-key nil
  "Key for Bing (Microsoft Azure) search API.

Can be a key string or a function that returns a key string.

Refer to URL `https://www.microsoft.com/en-us/bing/apis/bing-web-search-api'
and URL
`https://learn.microsoft.com/en-us/bing/search-apis/bing-web-search/search-the-web' for details on getting an API key."
  :group 'consult-omni
  :type '(choice (string :tag "API Key")
                 (function :tag "Custom Function")))

(defvar consult-omni-bing-search-api-url "https://api.bing.microsoft.com/v7.0/search"
  "API URL for Bing.")

(cl-defun consult-omni--bing-fetch-results (input &rest args &key callback &allow-other-keys)
  "Fetch search results for INPUT from Bing web search api with ARGS.

Refer to URL `https://programmablesearchengine.google.com/about/' and
`https://developers.google.com/custom-search/' for more info.

CALLBACK is a function used internally to update the list of candidates in
the minibuffer asynchronously.  It is called with a list of strings, which
are new annotated candidates \(e.g. as they arrive from an asynchronous
process\) to be added to the minibuffer completion cnadidates.  See the
section on REQUEST in documentation for `consult-omni-define-source' as
well as the function
`consult-omni--multi-update-dynamic-candidates' for how CALLBACK is used."
  (pcase-let* ((`(,query . ,opts) (consult-omni--split-command input (seq-difference args (list :callback callback))))
               (opts (car-safe opts))
               (count (plist-get opts :count))
               (page (plist-get opts :page))
               (count (or (and count (integerp (read count)) (string-to-number count))
                          consult-omni-default-count))
               (page (or (and page (integerp (read page)) (string-to-number page))
                         consult-omni-default-page))
               (count (max count 1))
               (page (* page count))
               (params `(("q" . ,(replace-regexp-in-string " " "+" query))
                         ("count" . ,(format "%s" count))
                         ("offset" . ,(format "%s" page))))
               (headers `(("Ocp-Apim-Subscription-Key" . ,(consult-omni-expand-variable-function consult-omni-bing-search-api-key)))))
    (consult-omni--fetch-url consult-omni-bing-search-api-url consult-omni-http-retrieve-backend
                             :encoding 'utf-8
                             :params params
                             :headers headers
                             :parser #'consult-omni--json-parse-buffer
                             :callback
                             (lambda (attrs)
                               (let* ((raw-results (map-nested-elt attrs '("webPages" "value")))
                                      (search-url (gethash "webSearchUrl" attrs))
                                      (annotated-results
                                       (mapcar (lambda (item)
                                                 (let*
                                                     ((source "Bing")
                                                      (url (format "%s" (gethash "url" item)))
                                                      (title (gethash "name" item))
                                                      (snippet (gethash "snippet" item))
                                                      (decorated (funcall consult-omni-default-format-candidate :source source :query query :url url :search-url search-url :title title :snippet snippet)))
                                                   (propertize decorated
                                                               :source source
                                                               :title title
                                                               :url url
                                                               :search-url search-url
                                                               :query query
                                                               :snippet snippet)))
                                               raw-results)))
                                 (when (and annotated-results (functionp callback))
                                   (funcall callback annotated-results))
                                 annotated-results)))))

;; Define the Bing Source
(consult-omni-define-source "Bing"
                            :narrow-char ?i
                            :type 'dynamic
                            :require-match nil
                            :face 'consult-omni-engine-title-face
                            :request #'consult-omni--bing-fetch-results
                            :on-new (apply-partially #'consult-omni-external-search-with-engine "Bing")
                            :preview-key consult-omni-preview-key
                            :search-hist 'consult-omni--search-history
                            :select-hist 'consult-omni--selection-history
                            :enabled (lambda () (bound-and-true-p consult-omni-bing-search-api-key))
                            :group #'consult-omni--group-function
                            :sort t
                            :interactive consult-omni-intereactive-commands-type
                            :annotate nil)

;;; provide `consult-omni-bing' module

(provide 'consult-omni-bing)

(add-to-list 'consult-omni-sources-modules-to-load 'consult-omni-bing)
;;; consult-omni-bing.el ends here
