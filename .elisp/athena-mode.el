;;; athena-mode-el -- Major mode for editing Athena files

;; Author: Scott Andrew Borton <scott@pp.htv.fi>
;; Created: 25 Sep 2000
;; Keywords: WPDL major-mode

;; Copyright (C) 2000 Scott Andrew Borton <scott@pp.htv.fi>

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be
;; useful, but WITHOUT ANY WARRANTY; without even the implied
;; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
;; PURPOSE.  See the GNU General Public License for more details.

;; You should have received a copy of the GNU General Public
;; License along with this program; if not, write to the Free
;; Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
;; MA 02111-1307 USA

;;; Commentary:
;; 
;; This mode is an example used in a tutorial about Emacs
;; mode creation. The tutorial can be found here:
;; http://two-wugs.net/emacs/mode-tutorial.html

;;; Code:
(defvar athena-mode-hook nil)
(defvar athena-mode-map nil
  "Keymap for Athena major mode.")

(if athena-mode-map nil
  (setq athena-mode-map (make-keymap)))

(setq auto-mode-alist
	  (append
	   '(("\\.ath\\'" . athena-mode))
	   auto-mode-alist))

(defconst athena-font-lock-keywords-1
  (list
   ; These define the beginning and end of each Athena entity definition
   ; "PARTICIPANT" "END_PARTICIPANT" "MODEL" "END_MODEL" "WORKFLOW"
   ; "END_WORKFLOW" "ACTIVITY" "END_ACTIVITY" "TRANSITION"
   ; "END_TRANSITION" "APPLICATION" "END_APPLICATION" "DATA" "END_DATA"
   ; "TOOL_LIST" "END_TOOL_LIST"
'("\\(->\\|a\\(?:nd\\|pply-method\\(?:\\)?\\|ss\\(?:ert\\|ume\\(?:-left\\)?\\)\\)\\|begin\\|c\\(?:lear-assumption-base\\|o\\(?:mputes\\|nd\\)\\)\\|d\\(?:begin\\|e\\(?:\\(?:clar\\|fin\\)e\\)\\|let\\(?:rec\\)?\\|match\\|omain\\)\\|exists\\(?:-unique\\)?\\|forall\\|iff?\\|let\\(?:rec\\)?\\|m\\(?:atch\\|ethod\\)\\|not\\|or\\|s\\(?:ome-\\(?:prop-con\\|var\\)\\|tructures\\|uppose-absurd\\)\\|val-of\\|while\\)" . font-lock-builtin-face))
  "Minimal highlighting expressions for Athena mode.")

(defconst athena-font-lock-keywords-2
  (append athena-font-lock-keywords-1
		  (list
				 ; These are some possible attributes of WPDL entities
			  ; "WPDL_VERSION" "VENDOR" "CREATED" "NAME" "DESCRIPTION"
			; "AUTHOR" "STATUS" "EXTENDED_ATTRIBUTE" "TYPE" "TOOLNAME"
					; "IN_PARAMETERS" "OUT_PARAMETERS" "DEFAULT_VALUE"
			; "IMPLEMENTATION" "PERFORMER" "SPLIT" "CONDITION" "ROUTE"
									  ; "JOIN" "OTHERWISE" "TO" "FROM"
		   '("\\<\\(AUTHOR\\|C\\(ONDITION\\|REATED\\)\\|DE\\(FAULT_VALUE\\|SCRIPTION\\)\\|EXTENDED_ATTRIBUTE\\|FROM\\|I\\(MPLEMENTATION\\|N_PARAMETERS\\)\\|JOIN\\|NAME\\|O\\(THERWISE\\|UT_PARAMETERS\\)\\|PERFORMER\\|ROUTE\\|S\\(PLIT\\|TATUS\\)\\|T\\(O\\(OLNAME\\)?\\|YPE\\)\\|VENDOR\\|WPDL_VERSION\\)\\>" . font-lock-keyword-face)
		   '("\\<\\(TRUE\\|FALSE\\)\\>" . font-lock-constant-face)))
  "Additional Keywords to highlight in WPDL mode.")

(defconst athena-font-lock-keywords-3
  (append athena-font-lock-keywords-2
		  (list
		 ; These are some possible built-in values for WPDL attributes
			 ; "ROLE" "ORGANISATIONAL_UNIT" "STRING" "REFERENCE" "AND"
			 ; "XOR" "WORKFLOW" "SYNCHR" "NO" "APPLICATIONS" "BOOLEAN"
							 ; "INTEGER" "HUMAN" "UNDER_REVISION" "OR"
		   '("\\<\\(A\\(ND\\|PPLICATIONS\\)\\|BOOLEAN\\|HUMAN\\|INTEGER\\|NO\\|OR\\(GANISATIONAL_UNIT\\)?\\|R\\(EFERENCE\\|OLE\\)\\|S\\(TRING\\|YNCHR\\)\\|UNDER_REVISION\\|WORKFLOW\\|XOR\\)\\>" . font-lock-constant-face)))
  "Balls-out highlighting in WPDL mode.")

(defvar athena-font-lock-keywords athena-font-lock-keywords-3
  "Default highlighting expressions for WPDL mode.")

(defun athena-indent-line ()
  "Indent current line as Athena code."
  (interactive)
  (beginning-of-line)
  (if (bobp)
	  (indent-line-to 0)		   ; First line is always non-indented
	(let ((not-indented t) cur-indent)
	  (if (looking-at "^[ \t]*END_") ; If the line we are looking at is the end of a block, then decrease the indentation
		  (progn
			(save-excursion
			  (forward-line -1)
			  (setq cur-indent (- (current-indentation) default-tab-width)))
			(if (< cur-indent 0) ; We can't indent past the left margin
				(setq cur-indent 0)))
		(save-excursion
		  (while not-indented ; Iterate backwards until we find an indentation hint
			(forward-line -1)
			(if (looking-at "^[ \t]*END_") ; This hint indicates that we need to indent at the level of the END_ token
				(progn
				  (setq cur-indent (current-indentation))
				  (setq not-indented nil))
			  (if (looking-at "^[ \t]*\\(PARTICIPANT\\|MODEL\\|APPLICATION\\|WORKFLOW\\|ACTIVITY\\|DATA\\|TOOL_LIST\\|TRANSITION\\)") ; This hint indicates that we need to indent an extra level
				  (progn
					(setq cur-indent (+ (current-indentation) default-tab-width)) ; Do the actual indenting
					(setq not-indented nil))
				(if (bobp)
					(setq not-indented nil)))))))
	  (if cur-indent
		  (indent-line-to cur-indent)
		(indent-line-to 0))))) ; If we didn't see an indentation hint, then allow no indentation

(defvar athena-mode-syntax-table nil
  "Syntax table for athena-mode.")

(defun athena-create-syntax-table ()
  (if athena-mode-syntax-table
	  ()
	(setq athena-mode-syntax-table (make-syntax-table))
	(set-syntax-table athena-mode-syntax-table)
	
    ; This is added so entity names with underscores can be more easily parsed
	(modify-syntax-entry ?_ "w" athena-mode-syntax-table)
  
	; Comment styles are same as C++
	(modify-syntax-entry ?/ ". 124b" athena-mode-syntax-table)
	(modify-syntax-entry ?* ". 23" athena-mode-syntax-table)
	(modify-syntax-entry ?\n "> b" athena-mode-syntax-table)))

(defun athena-mode ()
  "Major mode for editing Workflow Process Description Language files."
  (interactive)
  (kill-all-local-variables)
  (athena-create-syntax-table)
  
  ;; Set up font-lock
  (make-local-variable 'font-lock-defaults)
  (setq font-lock-defaults
		'(athena-font-lock-keywords))
  
  ;; Register our indentation function
  (make-local-variable 'indent-line-function)
  (setq indent-line-function 'athena-indent-line)
  
  (setq major-mode 'athena-mode)
  (setq mode-name "Athena")
  (run-hooks 'athena-mode-hook))

(provide 'athena-mode)

;;; athena-mode.el ends here



