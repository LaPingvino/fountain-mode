;;; fountain-export.el --- Export engine for Fountain Mode

;; Copyright (C) 2014  Paul Rankin

;; Author: Paul Rankin <paul@tilk.co>
;; Keywords: wp

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; 

;;; Code:

(defgroup fountain-export ()
  "Options for exporting Fountain files."
  :prefix 'fountain-export-
  :group 'fountain)

;;; customizable variables =============================================

(defcustom fountain-export-buffer-name
  "*Fountain Mode Export*"
  "Buffer name to use when not exporting a file."
  :type 'string
  :group 'fountain-export)

(defcustom fountain-export-fonts
  '("Courier Prime"
    "Courier Final Draft"
    "Courier Screenplay"
    "Courier"
    "Courier New")
  ""
  :type '(repeat (string :tag "Font"))
  :group 'fountain-export)

(defcustom fountain-export-html-head-template
  "<!DOCTYPE html>
<!-- Created with Emacs ${emacs-version} running Fountain Mode ${fountain-version} -->
<html>
<head>
<link rel=\"stylesheet\" href=\"${cssfile}\">
</head>
"
  "HTML template inserted into export buffer.
See `fountain-export-format-template'."
  :type 'string
  :group 'fountain-export)

;;; internal functions =================================================

(defun fountain-export-fontify-region (start end)
  "Fontify between START and END."
  (if font-lock-mode
      (let ((font-lock-maximum-decoration t)
            (job (make-progress-reporter "Fontifying... " 0 100))
            (chunk (/ end 100))
            (n 0))
        (goto-char start)
        (while (< (point) end)
          (let ((limit (+ (point) chunk)))
            (jit-lock-fontify-now (point) limit)
            (goto-char limit)
            (progress-reporter-update job n)
            (setq n (+ n 1))))
        (progress-reporter-done job))
    (error "Font Lock is not active")))

(defun fountain-export-get-name (buffer ext)
  "If BUFFER is visiting a file, concat file name base and EXT.
Otherwise return `fountain-export-buffer-name'"
  (if (buffer-file-name buffer)
      (concat (file-name-base (buffer-file-name buffer)) ext)
    fountain-export-buffer-name))

(defun fountain-export-filter (s)
  "Replace newlines with line-breaks and escape HTML special characters."
  (s-replace-all '(("&" . "&amp;")
                   ("<" . "&lt;")
                   (">" . "&gt;")
                   ("\n" . "<br>")) s))

(defun fountain-export-create-html-element (substring)
  "Return a HTML element with face and substring of SUBSTRING.
Stylesheet class is taken from face, while content is taken from
of SUBSTRING.

If face is `fountain-comment', return nil."
  (let* ((class
          (if (get-text-property 0 'face substring)
              (let* ((s (symbol-name (get-text-property 0 'face substring)))
                     (s (s-chop-suffix "-highlight" s))
                     (s (s-chop-prefix "fountain-" s))) s)
            "action"))
         (element (cond ((string= class "scene-heading")
                         "h1")
                        ((string= class "character")
                         "h2")
                        ("p")))
         (content
          (fountain-export-filter (substring-no-properties substring))))
    (unless (string= class "comment")
      (format "<%s class=\"%s\">%s</%s>\n"
              element class content element))))

(defun fountain-export-format-template (template sourcebuf)
  "Format TEMPLATE according to the following list.

Internal function, will not work outside of
`fountain-export-html'."
  (s-format template 'aget
            `(("fountain-version" . ,fountain-version)
              ("emacs-version" . ,emacs-version)
              ;; title?
              ;; author?
              ("htmlfile" . ,(fountain-export-get-name
                              sourcebuf ".html"))
              ("cssfile" . ,(fountain-export-get-name
                             sourcebuf ".css")))))

(defun fountain-export-parse-region (start end destbuf)
  "Find face property changes from START to END and insert HTML elements into DESTBUF.
First, find the next face property change from point, then pass
substring between point and change to
`fountain-export-create-html-element', then insert the newly
created HTML element to DESTBUF."
  (let ((job (make-progress-reporter "Parsing... " 0 100)))
    (goto-char start)
    (while (< (point) end)
      (skip-chars-forward "\n\s\t")
      (let* ((index (point))
             (limit (save-excursion
                      (re-search-forward "\n\s?\n\\|\\'" end t)
                      (match-beginning 0)))
             (change (next-single-property-change index 'face nil limit)))
        (when change
          (let* ((s (buffer-substring index change))
                 (element (fountain-export-create-html-element s)))
            (when element
              (with-current-buffer destbuf
                (with-silent-modifications
                  (insert element)))))
          (goto-char change)))
      (unless (looking-at ".\\|\\'")
        (forward-char 1))
      (progress-reporter-update
       job (truncate (* (/ (float (point)) (buffer-size)) 100))))))

(defun fountain-export-prepare-html ()
  ""
  (sgml-mode)
  (let ((sgml-unclosed-tags '("link" "br"))
        (job (make-progress-reporter "Preparing HTML... " 0 100)))
    (goto-char (point-min))
    (while (< (point) (point-max))
      (indent-according-to-mode)
      (forward-line 1)
      (progress-reporter-update
       job (truncate (* (/ (float (point)) (point-max)) 100))))
    (progress-reporter-done job)))

(defun fountain-export-pdf-buffer ()
  ""
  (interactive)
  (save-excursion
    (save-restriction
      (widen)
      ;; run `fountain-export-pdf-command'
      )))

(defun fountain-export-html-buffer ()
  ""
  (interactive)
  (save-excursion
    (save-restriction
      (widen)
      (fountain-export-html-region (point-min) (point-max)))))

(defun fountain-export-html-region (start end)
  "Convert region to HTML, writing result to new buffer."
  (interactive "r")
  (save-excursion
    ;; FIXME: create the stylesheet
    (let* ((job (make-progress-reporter "Exporting... " 0 100))
           (sourcebuf (current-buffer))
           (htmlbuf (generate-new-buffer
                     (fountain-export-get-name sourcebuf ".html")))
           complete)
      (unwind-protect
          (progn
            ;; fontify the region
            (fountain-export-fontify-region start end)
            ;; insert HTML head
            (with-current-buffer htmlbuf
              (with-silent-modifications
                (insert (fountain-export-format-template
                         fountain-export-html-head-template sourcebuf)
                        "<body>\n<div id=\"screenplay\">\n")))
            ;; parse the buffer
            (fountain-export-parse-region start end htmlbuf)
            ;; switch to destination buffer for final touches
            (switch-to-buffer-other-window htmlbuf)
            (insert "</div>\n</body>\n</html>")
            (fountain-export-prepare-html)
            (progress-reporter-done job)
            (setq complete t))
        (unless complete
          (kill-buffer htmlbuf))))))
      

(provide 'fountain-export)
;;; fountain-export.el ends here
