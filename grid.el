;;; grid.el --- Simple grid layout -*- lexical-binding: t; -*-

;; Copyright (C) 2024  Ilya Chernyshov

;; Author: Ilya Chernyshov <ichernyshovvv@gmail.com>
;; Version: 0.1-pre
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, docs, layout
;; URL: https://github.com/ichernyshovvv/grid

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; USAGE:
;; (grid-insert-rows '(ROW ROW ...))
;; ROW: '(BOX BOX ...)
;; BOX: plist.  Acceptable properties:

;;   :border
;;   nil or t

;;   :width
;;   "50%"
;;   integer (number of characters)

;;   :padding - horizontal padding
;;   integer (number of characters)

;;   :content - string to be inserted in the box

;;; Code:

(require 'subr-x)

(defvar grid-margin 1)

(defun grid-content-empty-p (box)
  "Non-nil if content of BOX is empty."
  (string-empty-p (plist-get box :content)))

(defvar grid-overline '((t (:overline t)))
  "Overline face.")

(defvar grid-underline
  '((t (:underline ( :color foreground-color :style line :position -3))))
  "Underline face.")

(defvar grid-vertical-borders '((t (:box (:line-width (1 . 0)))))
  "Vertical borders face.")

(defvar grid-invisible-box
  `((t (:box ( :line-width (1 . 0) :color ,(face-background 'default)))))
  "Invisible box face.")

(defun grid--apply-face (string face)
  "Apply FACE to STRING."
  (add-face-text-property
   0 (length string)
   face t string))

(defun grid--normalize-width (width)
  "Normalize WIDTH."
  (if (stringp width)
      (floor
       (* (window-width)
	  (/ (string-to-number width) 100.0)))
    width))

(defun grid--reformat-content (content width align)
  "Reformat CONTENT for a box with width WIDTH and align it accoring to ALIGN."
  (let (indent-tabs-mode prev-pos)
    (with-temp-buffer
      (insert content "\n")
      (goto-char (point-min))
      (setq prev-pos (point))
      (while (re-search-forward "\n" nil t)
	(replace-match " ")
	(let ((left (- width (% (match-beginning 0) width))))
	  (pcase align
	    ((or `nil `left)
	     (insert-char ?  left))
	    (`right
	     (save-excursion
	       (goto-char prev-pos)
	       (insert-char ?  left)))
	    (`center
	     (save-excursion
	       (goto-char prev-pos)
	       (insert-char ?  (ceiling left 2)))
	     (insert-char ?  (ceiling left 2)))))
	(setq prev-pos (point)))
      (buffer-string))))

(defun grid--longest-line-length (string)
  "Get the length of the longest line in STRING."
  (let ((lines (split-string string "\n")))
    (thread-last lines
		 (seq-map #'length)
		 (seq-max)
		 ;; FIX
		 (+ 2))))

(defun grid--normalize-box (box)
  "Return a normalized copy of BOX."
  (let* ((box (pcase box
		((pred plistp) (copy-tree box))
		((pred stringp) (list :content box))))
	 (content (plist-get box :content))
	 (align (plist-get box :align))
	 (padding (* (or (plist-get box :padding) 0) 2))
	 (width-raw
	  (or
	   (plist-get box :width)
	   (let ((width (grid--longest-line-length content)))
	     (setq box (plist-put box :width width))
	     width)))
	 (width (- (grid--normalize-width width-raw) padding)))
    (when (< width 0)
      (user-error "Horizonal padding must be less than width"))
    (setq box (plist-put box :content (grid--reformat-content content width align)))
    (setq box (plist-put box :length (length (plist-get box :content))))
    box))

(defun grid--insert-row (row)
  "Insert ROW in the current buffer."
  (while (not (seq-every-p #'grid-content-empty-p row))
    (mapc #'grid--insert-box row)
    (delete-char (* grid-margin -1))
    (insert ?\n))
  (insert ?\n))

(defun grid--insert-box (box)
  "Insert BOX in the current buffer."
  (let* ((content (plist-get box :content))
	 (content-len (length content))
	 (padding-len (or (plist-get box :padding) 0))
	 (padding (make-string padding-len ? ))
	 (width (- (grid--normalize-width
		    (plist-get box :width))
		   (* padding-len 2)))
	 (line-len (min content-len width))
	 (line (concat padding
		       (format (format "%% -%ds" width)
			       (substring content 0 line-len))
		       padding))
	 (donep (string-empty-p content))
	 (new-content (substring content line-len)))
    (when (plist-get box :border)
      (let ((faces (list
		    ;; first line?
		    (and (= (plist-get box :length)
			    content-len)
			 grid-overline)
		    ;; in body?
		    (and (/= content-len 0)
			 grid-vertical-borders)
		    ;; last line?
		    (and (and (not donep) (string-empty-p new-content))
			 grid-underline)
		    (and donep grid-invisible-box))))
	(thread-last
	  faces
	  (remove nil)
	  (mapc (apply-partially #'grid--apply-face line)))))
    (insert line)
    (insert-char ?  grid-margin)
    (setq box (plist-put box :content new-content))))

;;; API

(defun grid-insert-box (box)
  "Insert BOX in the current buffer."
  (grid-insert-row (list box)))

(defun grid-get-box (box)
  "Return BOX as a string."
  (grid-get-row (list box)))

(defun grid-insert-row (row)
  "Insert ROW in the current buffer."
  (grid--insert-row (mapcar #'grid--normalize-box row)))

(defun grid-insert-column (column)
  "Insert COLUMN in the current buffer."
  (grid-insert-rows (mapcar #'list column)))

(defun grid-get-column (column)
  "Return COLUMN as a string."
  (grid-get-rows (mapcar #'list column)))

(defun grid-insert-rows (rows)
  "Insert ROWS in the current buffer."
  (mapc #'grid-insert-row rows))

(defun grid-get-row (row)
  "Return ROW as a string."
  (with-temp-buffer
    (grid-insert-row row)
    (buffer-string)))

(defun grid-get-rows (rows)
  "Return ROWS as a string."
  (with-temp-buffer
    (grid-insert-rows rows)
    (buffer-string)))

(provide 'grid)

;;; grid.el ends here
