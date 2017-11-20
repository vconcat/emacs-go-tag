;;; gomodifytags.el --- Modify tags for struct fields -*- lexical-binding: t; -*-

;; Copyright (C) 2017 Brantou

;; Author: Brantou <brantou89@gmail.com>
;; URL: https://github.com/brantou/emacs-gomodifytags
;; Keywords: tools
;; Version: 0.0.1
;; Package-Requires: ((emacs "24.0"))

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;; This file is not part of GNU Emacs.

;;; Commentary:
;;
;; Modify field tags for struct. Based on https://github.com/fatih/gomodifytags
;;

;;; Requirements:
;;
;; - gomodifytags :: https://github.com/fatih/gomodifytags
;;

;;; TODO
;;
;; - Provide better error feedback.
;; - Provide more configuration.
;;

;;; Code:

(require 'go-mode)

(defgroup gomodifytags nil
  "Modify field tag for struct fields."
  :group 'go)

(defcustom gomodifytags-command "gomodifytags"
  "The 'gomodifytags' command.
from https://github.com/fatih/gomodifytags."
  :type 'string
  :group 'go)

(defcustom gomodifytags-args nil
  "Additional arguments to pass to gomodifytags."
  :type '(repeat string)
  :group 'go)

(defcustom gomodifytags-show-errors 'buffer
  "Where to display gomodifytags error output.
It can either be displayed in its own buffer, in the echo area, or not at all."
  :type '(choice
          (const :tag "Own buffer" buffer)
          (const :tag "Echo area" echo)
          (const :tag "None" nil))
  :group 'go)

;;;###autoload
(defun gomodifytags (tags)
  "Add field TAGS for struct fields."
  (interactive "sTags:")
  (if (use-region-p)
      (gomodifytags--region (region-beginning) (region-end) tags nil)
    (gomodifytags--point (point) tags nil)))

(defun gomodifytags--region (start end tags &optional options)
  "Add field TAGS for the region between START and END."
  (let ((cmd-args (append
                   gomodifytags-args
                   (list "-line" (format "%S,%S" (line-number-at-pos start) (line-number-at-pos end))))))
    (gomodifytags--add cmd-args tags options)))

(defun gomodifytags--point (point tags &optional options)
  "Add field TAGS for the struct under the POINT."
  (let ((cmd-args (append gomodifytags-args
                          (list "-offset" (format "%S" point)))))
    (gomodifytags--add cmd-args tags options)))

(defun gomodifytags--add (cmd-args tags &optional options)
  "Init CMD-ARGS, add TAGS and OPTIONS to CMD-ARGS."
  (progn
    (when tags
      (setq cmd-args
            (append cmd-args
                    (list "-add-tags" tags))))
    (when options
      (setq cmd-args
            (append cmd-args
                    (list "-add-options" options))))
    (gomodifytags--proc cmd-args)))

;;;###autoload
(defun gomodifytags-remove (tags)
  "Remove field TAGS for struct fields."
  (interactive "sTags:")
  (if (use-region-p)
      (gomodifytags--region-remove (region-beginning) (region-end) tags nil)
    (gomodifytags--point-remove (point) tags nil)))

(defun gomodifytags--region-remove (start end tags &optional options)
  "Remove field TAGS for the region between START and END."
  (let ((cmd-args (append
                   gomodifytags-args
                   (list "-line" (format "%S,%S" (line-number-at-pos start) (line-number-at-pos end))))))
    (gomodifytags--remove cmd-args tags options)))

(defun gomodifytags--point-remove (point tags &optional options)
  "Add field TAGS for the struct under the POINT."
  (let ((cmd-args (append
                   gomodifytags-args
                   (list "-offset" (format "%S" point)))))
    (gomodifytags--remove cmd-args tags options)))

(defun gomodifytags--remove(cmd-args tags &optional options)
  "Init CMD-ARGS, add TAGS and OPTIONS to CMD-ARGS."
  (progn
    (when tags
      (setq cmd-args
            (append cmd-args
                    (list "-remove-tags" tags))))
    (when options
      (setq cmd-args
            (append cmd-args
                    (list "-remove-options" options))))
    (gomodifytags--proc cmd-args)))

(defun gomodifytags--proc (cmd-args)
  "Modify field tags based on CMD-ARGS.

  The tool used can be set via ‘gomodifytags-command` (default: gomodifytags)
 and additional arguments can be set as a list via ‘gomodifytags-args`."
  (let ((tmpfile (make-temp-file "gomodifytags" nil ".go"))
        (patchbuf (get-buffer-create "*Gomodifytags patch*"))
        (errbuf (if gomodifytags-show-errors
                    (get-buffer-create "*Gomodifytags Errors*")))
        (coding-system-for-read 'utf-8)
        (coding-system-for-write 'utf-8))

    (unwind-protect
        (save-restriction
          (widen)
          (if errbuf
              (with-current-buffer errbuf
                (setq buffer-read-only nil)
                (erase-buffer)))
          (with-current-buffer patchbuf
            (erase-buffer))

          (write-region nil nil tmpfile)

          (setq cmd-args (append cmd-args (list "-file" tmpfile "-w")))

          (message "Calling gomodifytags: %s %s" gomodifytags-command cmd-args)
          (if (zerop (apply #'call-process gomodifytags-command nil errbuf nil cmd-args))
              (progn
                (if (zerop (call-process-region (point-min) (point-max) "diff" nil patchbuf nil "-n" "-" tmpfile))
                    (message "Buffer is already gomodifytags")
                  (go--apply-rcs-patch patchbuf)
                  (message "Applied gomodifytags"))
                (if errbuf (gomodifytags--kill-error-buffer errbuf)))
            (message "Could not apply gomodifytags")
            (if errbuf
                (progn
                  (message (with-current-buffer errbuf (buffer-string)))
                  (gomodifytags--kill-error-buffer errbuf)))))

      (kill-buffer patchbuf)
      (delete-file tmpfile))))

(defun gomodifytags--kill-error-buffer (errbuf)
  "Kill ERRBUF."
  (let ((win (get-buffer-window errbuf)))
    (if win
        (quit-window t win)
      (kill-buffer errbuf))))

(provide 'gomodifytags)

;;; gomodifytags.el ends here
