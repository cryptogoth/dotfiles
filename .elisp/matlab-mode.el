;;; matlab.el --- major mode for MATLAB dot-m files
;;
;; Author: Matt Wette <mwette@alumni.caltech.edu>,
;;         Eric M. Ludlam <eludlam@mathworks.com>
;; Maintainer: Eric M. Ludlam <eludlam@mathworks.com>
;; Created: 04 Jan 91
;; Version: 2.1.1
;; Keywords: Matlab
;;
;; LCD Archive Entry:
;; matlab|Eric M. Ludlam|eludlam@mathworks.com|
;; Major mode for editing and debugging MATLAB dot-m files|
;; 03-Jun-98|2.1.1|~/modes/matlab.el.gz|
;;
;; Copyright (C) 1991-1997 Matthew R. Wette
;; Copyright (C) 1997-1998 Eric M. Ludlam
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.
;;
;;; Commentary:
;;
;; This major mode for GNU Emacs provides support for editing MATLAB dot-m
;; files.  It automatically indents for block structures, line continuations
;; (e.g., ...), and comments.
;;
;; Additional features include auto-fill including auto-additions of
;; ellipsis for commands, and even strings.  Block/end construct
;; highlighting as you edit.  Primitive code-verification and
;; identification.  Templates and other code editing functions.
;; Advanced symbol completion.  Code highlighting via font-lock.
;; There are many navigation commands that let you move across blocks
;; of code at different levels.
;;
;; Lastly, there is support for running Matlab in an Emacs buffer,
;; with full shell history and debugger support (when used with the db
;; commands.)  The shell can be used as an online help while editing
;; code, providing help on functions, variables, or running arbitrary
;; blocks of code from the buffer you are editing.
;;
;; Installation:
;;   Put the this file as "matlab.el" somewhere on your load path, then
;;   add this to your .emacs or site-init.el file:
;;
;;   (autoload 'matlab-mode "matlab" "Enter Matlab mode." t)
;;   (setq auto-mode-alist (cons '("\\.m\\'" . matlab-mode) auto-mode-alist))
;;   (autoload 'matlab-shell "matlab" "Interactive Matlab mode." t)
;;
;; User Level customizations:
;;   (setq matlab-indent-function t)	; if you want function bodies indented
;;   (setq matlab-verify-on-save-flag nil) ; turn off auto-verify on save
;;   (defun my-matlab-mode-hook ()
;;     (setq fill-column 76))		; where auto-fill should wrap
;;   (add-hook 'matlab-mode-hook 'my-matlab-mode-hook)
;;   (defun my-matlab-shell-mode-hook ()
;;	'())
;;   (add-hook 'matlab-shell-mode-hook 'my-matlab-shell-mode-hook)
;;
;; Syntax highlighting:
;;   To get font-lock try adding
;;     (font-lock-mode 1)
;;   Or for newer versions of Emacs
;;     (global-font-lock-mode t)
;;   To get hilit19 support try adding
;;     (matlab-mode-hilit)
;;
;; This package requires easymenu, tempo, and derived.

;;; Mailing List:
;;
;; A mailing list has been set up where beta versions of matlab.el are posted,
;; and where comments, questions, and bug reports, and answers to
;; questions can be sent.
;;
;; To subscribe send email to "lists@mathworks.com" with a body of:
;;    "subscribe matlab-emacs"
;; to unsubscribe, send email with the body of: "unsubscribe matlab-emacs"

;;; Code:

;;(setq debug-on-error t)

(require 'easymenu)
(require 'tempo)
(require 'derived)

(defconst matlab-mode-version "2.1.1"
  "Current version of Matlab mode.")

;; From custom web page for compatibility between versions of custom:
(eval-and-compile
  (condition-case ()
      (require 'custom)
    (error nil))
  (if (and (featurep 'custom) (fboundp 'custom-declare-variable))
      nil ;; We've got what we needed
    ;; We have the old custom-library, hack around it!
    (defmacro defgroup (&rest args)
      nil)
    (defmacro custom-add-option (&rest args)
      nil)
    (defmacro defface (&rest args) nil)
    (defmacro defcustom (var value doc &rest args)
      (` (defvar (, var) (, value) (, doc))))))

;; compatibility
(if (string-match "X[Ee]macs" emacs-version)
    (progn
      (defalias 'matlab-make-overlay 'make-extent)
      (defalias 'matlab-overlay-put 'set-extent-property)
      (defalias 'matlab-delete-overlay 'delete-extent)
      (defalias 'matlab-overlay-start 'extent-start)
      (defalias 'matlab-overlay-end 'extent-end)
      (defalias 'matlab-cancel-timer 'delete-itimer)
      (defun matlab-run-with-idle-timer (secs repeat function &rest args)
	(condition-case nil
	    (start-itimer "matlab" function secs (if repeat secs nil) t)
	  (error
	   ;; If the above doesn't work, then try this old version of start itimer.
	   (start-itimer "matlab" function secs (if repeat secs nil)))))
      )
  (defalias 'matlab-make-overlay 'make-overlay)
  (defalias 'matlab-overlay-put 'overlay-put)
  (defalias 'matlab-delete-overlay 'delete-overlay)
  (defalias 'matlab-overlay-start 'overlay-start)
  (defalias 'matlab-overlay-end 'overlay-end)
  (defalias 'matlab-cancel-timer 'cancel-timer)
  (defalias 'matlab-run-with-idle-timer 'run-with-idle-timer)
  )

(if (fboundp 'point-at-bol)
    (progn
      (defalias 'matlab-point-at-bol 'point-at-bol)
      (defalias 'matlab-point-at-eol 'point-at-eol))
  (defun matlab-point-at-bol ()
    (interactive) (save-excursion (beginning-of-line) (point)))
  (defun matlab-point-at-eol ()
    (interactive) (save-excursion (end-of-line) (point))))


;;; User-changeable variables =================================================

;; Variables which the user can change
(defgroup matlab nil
  "Matlab mode."
  :prefix "matlab-"
  :group 'languages)

(defcustom matlab-indent-level 2
  "*The indentation in `matlab-mode'."
  :group 'matlab
  :type 'integer)

(defcustom matlab-cont-level 4
  "*Continuation indent."
  :group 'matlab
  :type 'integer)

(defcustom matlab-fill-code t
  "*If true, `auto-fill-mode' causes code lines to be automatically continued."
  :group 'matlab
  :type 'boolean)

(defcustom matlab-auto-fill t
  "*If true, set variable `auto-fill-function' to our function at startup."
  :group 'matlab
  :type 'boolean)

(defcustom matlab-fill-count-ellipsis-flag t
  "*Non-nil means to count the ellipsis when auto filling.
This effectively shortens the `fill-column' by 3.")

(defcustom matlab-fill-strings-flag t
  "*Non-nil means that when auto-fill is on, strings are broken across lines.
If `matlab-fill-count-ellipsis-flag' is non nil, this shortens the
`fill-column' by 4.")

(defcustom matlab-comment-column 40
  "*The goal comment column in `matlab-mode' buffers."
  :group 'matlab
  :type 'integer)

(defcustom matlab-comment-line-s "% "
  "*String to start comment on line by itself."
  :group 'matlab
  :type 'string)

(defcustom matlab-comment-on-line-s "% "
  "*String to start comment on line with code."
  :group 'matlab
  :type 'string)

(defcustom matlab-comment-region-s "% $$$ "
  "*String inserted by \\[matlab-comment-region] at start of each line in \
region."
  :group 'matlab
  :type 'string)

(defcustom matlab-indent-function nil
  "*If t, indent body of function."
  :group 'matlab
  :type 'boolean)

(defcustom matlab-verify-on-save-flag t
  "*Non-nil means to verify M whenever we save a file."
  :group 'matlab
  :type 'boolean)

(defcustom matlab-block-verify-max-buffer-size 50000
  "*Largest buffer size allowed for block verification during save."
  :group 'matlab
  :type 'integer)

(defcustom matlab-vers-on-startup t
  "*If non-nil, show the version number on startup."
  :group 'matlab
  :type 'boolean)

(defcustom matlab-highlight-block-match-flag t
  "*Non-nil means to highlight the matching if/end/whatever.
The highlighting only occurs when the cursor is on a block start or end
keyword."
  :group 'matlab
  :type 'boolean)

(defcustom matlab-show-periodic-code-details-flag nil
  "*Non-nil means to show code details in the minibuffer.
This will only work if `matlab-highlight-block-match-flag' is non-nil."
  :group 'matlab
  :type 'boolean)

(defcustom matlab-mode-hook nil
  "*List of functions to call on entry to Matlab mode."
  :group 'matlab
  :type 'hook)

(defcustom matlab-completion-technique 'complete
  "*How the `matlab-complete-symbol' interfaces with the user.
Valid values are:

'increment - which means that new strings are tried with each
             successive call until all methods are exhausted.
             (Similar to `hippie-expand'.)
'complete  - Which means that if there is no single completion, then
             all possibilities are displayed in a completion buffer."
  :group 'matlab
  :type '(radio (const :tag "Incremental completion (hippie-expand)."
		       increment)
		(const :tag "Show completion buffer."
		       complete)))

(if (and (featurep 'custom) (fboundp 'custom-declare-variable))

    ;; If we have custom, we can make our own special face like this
    (defface matlab-region-face '((t (:background "gray65")))
      "*Face used to highlight a matlab region."
      :group 'matlab)
  
  ;; If we do not, then we can fake it by copying 'region.
  (cond ((facep 'region)
	 (copy-face 'region 'matlab-region-face))
	(t
	 (copy-face 'zmacs-region 'matlab-region-face))))

;; Now, lets make the unterminated string face

(if (facep 'font-lock-string-face)
    (progn
      (copy-face 'font-lock-string-face 'matlab-unterminated-string-face)
      (set-face-underline-p 'matlab-unterminated-string-face t)))

(defvar matlab-unterminated-string-face 'matlab-unterminated-string-face
  "Self reference for unterminated string face.")


;;; Matlab mode variables =====================================================

(defvar matlab-tempo-tags nil
  "List of templates used in Matlab mode.")

;; syntax table
(defvar matlab-mode-syntax-table
  (let ((st (make-syntax-table (standard-syntax-table))))
    (modify-syntax-entry ?_  "_" st)
    (modify-syntax-entry ?%  "<" st)
    (modify-syntax-entry ?\n ">" st)
    (modify-syntax-entry ?\\ "." st)
    (modify-syntax-entry ?\t " " st)
    (modify-syntax-entry ?+  "." st)
    (modify-syntax-entry ?-  "." st)
    (modify-syntax-entry ?*  "." st)
    (modify-syntax-entry ?'  "." st)
    (modify-syntax-entry ?/  "." st)
    (modify-syntax-entry ?=  "." st)
    (modify-syntax-entry ?<  "." st)
    (modify-syntax-entry ?>  "." st)
    (modify-syntax-entry ?&  "." st)
    (modify-syntax-entry ?|  "." st)
    st)
  "The syntax table used in `matlab-mode' buffers.")

(defvar matlab-mode-special-syntax-table
  (let ((st (copy-syntax-table matlab-mode-syntax-table)))
    ;; Make _ a part of words so we can skip them better
    (modify-syntax-entry ?_  "w" st)
    st)
  "The syntax table used when navigating blocks.")

;; abbrev table
(defvar matlab-mode-abbrev-table nil
  "The abbrev table used in `matlab-mode' buffers.")

(define-abbrev-table 'matlab-mode-abbrev-table ())

;;; Keybindings ===============================================================

(defvar matlab-help-map
  (let ((km (make-sparse-keymap)))
    (define-key km "r" 'matlab-shell-run-command)
    (define-key km "f" 'matlab-shell-describe-command)
    (define-key km "a" 'matlab-shell-apropos)
    (define-key km "v" 'matlab-shell-describe-variable)
    (define-key km "t" 'matlab-shell-topic-browser)
    km)
  "The help key map for `matlab-mode' and `matlab-shell-mode'.")

(defvar matlab-insert-map
  (let ((km (make-sparse-keymap)))
    (define-key km "c" 'matlab-insert-next-case)
    (define-key km "e" 'matlab-insert-end-block)
    (define-key km "i" 'tempo-template-matlab-if)
    (define-key km "I" 'tempo-template-matlab-if-else)
    (define-key km "f" 'tempo-template-matlab-for)
    (define-key km "s" 'tempo-template-matlab-switch)
    (define-key km "t" 'tempo-template-matlab-try)
    (define-key km "w" 'tempo-template-matlab-while)
    (define-key km "F" 'tempo-template-matlab-function)
    (define-key km "'" 'matlab-stringify-region)
    km)
  "Keymap used for inserting simple texts based on context.")

;; mode map
(defvar matlab-mode-map
  (let ((km (make-sparse-keymap)))
    (define-key km [return] 'matlab-return)
    (define-key km "\C-c;" 'matlab-comment-region)
    (define-key km [(control c) return] 'matlab-comment-return)
    (define-key km [(control c) (control c)] matlab-insert-map)
    (define-key km [(control c) (control f)] 'matlab-fill-comment-line)
    (define-key km [(control c) (control j)] 'matlab-justify-line)
    (define-key km [(control c) (control q)] 'matlab-fill-region)
    (define-key km [(control c) (control s)] 'matlab-shell-save-and-go)
    (define-key km [(control c) (control r)] 'matlab-shell-run-region)
    (define-key km [(control c) (control t)] 'matlab-show-line-info)
    (define-key km [(control c) ?. ] 'matlab-find-file-on-path)
    (define-key km [(control h) (control m)] matlab-help-map)
    (define-key km [(control j)] 'matlab-linefeed)
    (define-key km [(meta return)] 'newline)
    (define-key km [(meta \;)] 'matlab-comment)
    (define-key km [(meta q)] 'matlab-fill-paragraph)
    (define-key km [(meta a)] 'matlab-beginning-of-command)
    (define-key km [(meta e)] 'matlab-end-of-command)
    (define-key km [(meta tab)] 'matlab-complete-symbol)
    (define-key km [(meta control f)] 'matlab-forward-sexp)
    (define-key km [(meta control b)] 'matlab-backward-sexp)
    (define-key km [(meta control a)] 'matlab-beginning-of-defun)
    (define-key km [(meta control e)] 'matlab-end-of-defun)
    (if (string-match "XEmacs" emacs-version)
	(define-key km [(control meta button1)] 'matlab-find-file-click)
      (define-key km [(control meta mouse-2)] 'matlab-find-file-click))
    (substitute-key-definition 'comment-region 'matlab-comment-region
			       km) ; global-map ;torkel
    km)
  "The keymap used in `matlab-mode'.")

;;; Font locking keywords =====================================================

(defvar matlab-string-start-regexp "\\(^\\|[^]})a-zA-Z0-9_.']\\)"
  "Regexp used to represent the character before the string char '.
The ' character has restrictions on what starts a string which is needed
when attempting to understand the current context.")

(defvar matlab-string-end-regexp "[^'\n]*\\(''[^'\n]*\\)*'"
  "Regexp used to represent the character pattern for ending a string.
The ' character can be used as a transpose, and can transpose transposes.
Therefore, to end, we must check all that goop.")

;; font-lock keywords
(defvar matlab-font-lock-keywords
  (list
   ;; String quote chars are also used as transpose, but only if directly
   ;; after characters, numbers, underscores, or closing delimiters.
   ;; To quote a quote, put two in a row, thus we need an anchored
   ;; first quote.  In addition, we don't want to color strings in comments.
   (list (concat matlab-string-start-regexp
		 "\\('" matlab-string-end-regexp "\\)")
	 2 '(if (matlab-cursor-in-comment) nil font-lock-string-face))
   ;; A string with no termination is not currently highlighted.
   ;; This will show that the string needs some attention.
   (list (concat matlab-string-start-regexp
		 "\\('[^'\n]*\\(''[^'\n]*\\)*\\)$")
	 2 '(if (matlab-cursor-in-comment) nil
	      matlab-unterminated-string-face))
   ;; Comments must occur after the string, that way we can check to see
   ;; if the comment start char has occurred inside our string. (EL)
   ;; (match-beginning 1) doesn't work w/ xemacs -- use 0 instead
   '("\\(%[^%\n]*\\)"
     1 (if (eq (get-text-property (match-beginning 0) 'face)
               font-lock-string-face) nil
         font-lock-comment-face) prepend)
   ;; General keywords
   ;;    (make-regexp '("global" "for" "while" "if" "elseif" "else"
   ;;    "endfunction" "return" "break" "switch" "case" "otherwise" "try"
   ;;    "catch"))
   '("\\<\\(break\\|ca\\(se\\|tch\\)\\|e\\(lse\\(\\|if\\)\\|ndfunction\\)\\|for\\|global\\|if\\|otherwise\\|return\\|switch\\|try\\|while\\)\\>"
     (0 font-lock-keyword-face))
   ;; The end keyword is only a keyword when not used as an array
   ;; dereferencing part.
   '("\\(^\\|[;,]\\)[ \t]*\\(end\\)\\b"
     2 (if (matlab-valid-end-construct-p) font-lock-keyword-face nil))
   ;; The global keyword defines some variables.  Mark them.
   '("^\\s-*global\\s-+"
     ("\\(\\w+\\)\\([ \t;]+\\|$\\)" nil nil (1 font-lock-variable-name-face)))
   ;; handle graphics cool stuff
   ;;   (make-regexp '("figure" "axes" "axis" "line" "surface" "patch"
   ;;		  "text" "light" "image" "set" "get" "uicontrol"
   ;;		  "uicontext" "uicontextmenu" "setfont" "setcolor"))
   '("\\<\\(ax\\(es\\|is\\)\\|figure\\|get\\|image\\|li\\(ght\\|ne\\)\\|patch\\|s\\(et\\(\\|color\\|font\\)\\|urface\\)\\|text\\|uicont\\(ext\\(\\|menu\\)\\|rol\\)\\)\\>"
     (0 font-lock-type-face))
   )
  "Expressions to highlight in Matlab mode.")

(defvar matlab-gaudy-font-lock-keywords
  (append
   matlab-font-lock-keywords
   (list
    ;; defining a function, a (possibly empty) list of assigned variables,
    ;; function name, and an optional (possibly empty) list of input variables
    (list (concat "^\\s-*\\(function\\)\\>[ \t\n.]*"
		  "\\(\\[[^]]*\\]\\|\\sw+\\)[ \t\n.]*"
		  "=[ \t\n.]*\\(\\sw+\\)[ \t\n.]*"
		  "\\(([^)]*)\\)?\\s-*[,;\n%]")
	  '(1 font-lock-keyword-face)
	  '(2 font-lock-variable-name-face)
	  '(3 font-lock-function-name-face))
    ;; defining a function, a function name, and an optional (possibly
    ;; empty) list of input variables
    (list (concat "^\\s-*\\(function\\)[ \t\n.]+"
		  "\\(\\sw+\\)[ \t\n.]*"
		  "\\(([^)]*)\\)?\\s-*[,;\n%]")
	  '(1 font-lock-keyword-face)
	  '(2 font-lock-function-name-face))
    ;; Anchor on the function keyword, highlight params
    (list (concat "^\\s-*function\\>[ \t\n.]*"
		  "\\(\\(\\[[^]]*\\]\\|\\sw+\\)[ \t\n.]*=[ \t\n.]*\\)?"
		  "\\sw+\\s-*(")
	  '("\\s-*\\(\\sw+\\)\\s-*[,)]" nil nil
	    (1 font-lock-variable-name-face)))
    ;; I like variables for FOR loops
    '("\\<\\(for\\)\\s-+\\(\\sw+\\)\\s-*=\\s-*\\([^\n,%]+\\)"
      (1 font-lock-keyword-face)
      (2 font-lock-variable-name-face)
      (3 font-lock-reference-face))
    ;; Items after a switch statements are cool
    '("\\<\\(case\\|switch\\)\\s-+\\({[^}\n]+}\\|[^,%\n]+\\)"
      (1 font-lock-keyword-face) (2 font-lock-reference-face))
    ;; How about a few matlab constants such as pi, infinity, and sqrt(-1)?
    ;; The ^>> is in case I use this in an interactive mode someday
    '("\\<\\(eps\\|pi\\|inf\\|Inf\\|NaN\\|nan\\|ans\\|i\\|j\\|^>>\\)\\>"
      1 font-lock-reference-face)
    ;; Define these as variables since this is about as close
    ;; as matlab gets to variables
    '("\\(set\\|get\\)\\s-*(\\s-*\\(\\w+\\)\\s-*\\(,\\|)\\)"
      2 font-lock-variable-name-face)
    ))
  "Expressions to highlight in Matlab mode.")


(defvar matlab-really-gaudy-font-lock-keywords
  (append
   matlab-gaudy-font-lock-keywords
   (list
    ;; Since it's a math language, how bout dem symbols?
    '("\\([<>~]=?\\|\\.[*^']\\|==\\|\\<xor\\>\\|[-!^&|*+\\/~:]\\)"
      1 font-lock-type-face)
    ;; How about the special help comments
    ;;'("function[^\n]+"
    ;;  ("^%\\([^\n]+\\)\n" nil nil (1 font-lock-reference-face t)))
    ;; continuation ellipsis.
    '("[^.]\\(\\.\\.\\.+\\)\\([^\n]*\\)" (1 'underline)
      (2 font-lock-comment-face))
    ;; How about debugging statements?
    ;;'("\\<\\(db\\sw+\\)\\>" 1 'bold)
    ;;(make-regexp '("dbstop" "dbclear" "dbcont" "dbdown" "dbmex"
    ;;		   "dbstack" "dbstatus" "dbstep" "dbtype" "dbup" "dbquit"))
    '("\\<\\(db\\(c\\(lear\\|ont\\)\\|down\\|mex\\|quit\\|st\\(a\\(ck\\|tus\\)\\|ep\\|op\\)\\|type\\|up\\)\\)\\>" (0 'bold))
    ;; Correct setting of the syntax table and other variables
    ;; will automatically handle this
    ;; '("%\\s-+.*" 0 font-lock-comment-face t)
    ))
  "Expressions to highlight in Matlab mode.")

(defvar matlab-shell-font-lock-keywords
  (list
   ;; How about Errors?
   '("^\\(Error in\\|Syntax error in\\)\\s-+==>\\s-+\\(.+\\)$"
     (1 font-lock-comment-face) (2 font-lock-string-face))
   ;; and line numbers
   '("^\\(On line [0-9]+\\)" 1 font-lock-comment-face)
   ;; User beep things
   '("\\(\\?\\?\\?[^\n]+\\)" 1 font-lock-comment-face)
   ;; Useful user commands, but not useful programming constructs
   '("\\<\\(demo\\|whatsnew\\|info\\|subscribe\\|help\\|doc\\|lookfor\\|what\
\\|whos?\\|cd\\|clear\\|load\\|save\\|helpdesk\\|helpwin\\)\\>"
     1 font-lock-keyword-face)
   ;; Various notices
   '(" M A T L A B (R) " 0 'underline)
   '("All Rights Reserved" 0 'italic)
   '("\\((c)\\s-+Copyright[^\n]+\\)" 1 font-lock-comment-face)
   '("\\(Version\\)\\s-+\\([^\n]+\\)"
     (1 font-lock-function-name-face) (2 font-lock-variable-name-face))
   )
  "Additional keywords used by Matlab when reporting errors in interactive\
mode.")


;; hilit19 patterns
(defvar matlab-hilit19-patterns
  '(
    ("\\(^\\|[^%]\\)\\(%[ \t].*\\|%\\)$" 2 comment)
    ("\\(^\\|[;,]\\)[ \t]*\\(\
function\\|global\\|for\\|while\\|if\\|elseif\\|else\\|end\\(function\\)?\
\\|return\\|switch\\|case\\|otherwise\\)\\b" 2 keyword)))

(defvar matlab-imenu-generic-expression
  '((nil "^\\s-*function\\>[ \t\n.]*\\(\\(\\[[^]]*\\]\\|\\sw+\\)[ \t\n.]*=[ \t\n.]*\\)?\\([a-zA-Z0-9_]+\\)"
	 3))
  "Expressions which find function headings in Matlab M files.")


;;; Matlab mode entry point ==================================================

;;;###autoload
(defun matlab-mode ()
  "Matlab-mode is a major mode for editing MATLAB dot-m files.

Variables:
  `matlab-indent-level'		Level to indent blocks.
  `matlab-comment-column'       Goal column for on-line comments.
  `fill-column'			Column used in auto-fill.
  `matlab-comment-line-s'       String to start comment line.
  `matlab-comment-region-s'	String to put comment lines in region.
  `matlab-vers-on-startup'	If t, show version on start-up.
  `matlab-indent-function'	If t, indents body of MATLAB functions.
  `matlab-hilit19-patterns'	Patterns for hilit19
  `matlab-font-lock-keywords'	Keywords for function `font-lock-mode'
  `matlab-return-function'	Customize RET handling with this function
  `matlab-auto-fill'            Non-nil, do auto-fill at startup
  `matlab-verify-on-save-flag'  Non-nil, enable code checks on save
  `matlab-highlight-block-match-flag'
                                Enable matching block begin/end keywords

To add automatic support put something like the following in your .emacs file:
  (autoload 'matlab-mode \"matlab\" \"Enter Matlab mode.\" t)
  (setq auto-mode-alist (cons '(\"\\\\.m\\\\'\" . matlab-mode) auto-mode-alist))
  (defun my-matlab-mode-hook ()
    (setq fill-column 76))
  (add-hook 'matlab-mode-hook 'my-matlab-mode-hook)

Special Key Bindings:
\\{matlab-mode-map}"
  (interactive)
  (kill-all-local-variables)
  (use-local-map matlab-mode-map)
  (setq major-mode 'matlab-mode)
  (setq mode-name "Matlab")
  (setq local-abbrev-table matlab-mode-abbrev-table)
  (set-syntax-table matlab-mode-syntax-table)
  (make-local-variable 'indent-line-function)
  (setq indent-line-function 'matlab-indent-line)
  (make-local-variable 'paragraph-start)
  (setq paragraph-start (concat "^$\\|" page-delimiter))
  (make-local-variable 'paragraph-separate)
  (setq paragraph-separate paragraph-start)
  (make-local-variable 'paragraph-ignore-fill-prefix)
  (setq paragraph-ignore-fill-prefix t)
  (make-local-variable 'comment-start-skip)
  (setq comment-start-skip "%\\s-+")
  (make-local-variable 'comment-start)
  (setq comment-start "%")
  (make-local-variable 'comment-column)
  (setq comment-column 'matlab-comment-column)
  (make-local-variable 'comment-indent-function)
  (setq comment-indent-function 'matlab-comment-indent)
  (make-local-variable 'fill-column)
  (setq fill-column default-fill-column)
  (make-local-variable 'auto-fill-function)
  (if matlab-auto-fill (setq auto-fill-function 'matlab-auto-fill))
  ;; Emacs 20 supports this variable.  This lets users turn auto-fill
  ;; on and off and still get the right fill function.
  (make-local-variable 'normal-auto-fill-function)
  (setq normal-auto-fill-function 'matlab-auto-fill)
  (make-local-variable 'fill-prefix)
  (make-local-variable 'imenu-generic-expression)
  (setq imenu-generic-expression matlab-imenu-generic-expression)
  ;; Save hook for verifying src.  This lets us change the name of
  ;; the function in `write-file' and have the change be saved.
  ;; It also lets us fix mistakes before a `save-and-go'.
  (make-local-variable 'write-contents-hooks)
  (add-hook 'write-contents-hooks 'matlab-mode-verify-fix-file-fn)
  ;; Tempo tags
  (make-local-variable 'tempo-local-tags)
  (setq tempo-local-tags (append matlab-tempo-tags tempo-local-tags))
  ;; give each file it's own parameter history
  (make-local-variable 'matlab-shell-save-and-go-history)
  (make-local-variable 'font-lock-defaults)
  (setq font-lock-defaults '((matlab-font-lock-keywords
			      matlab-gaudy-font-lock-keywords
			      matlab-really-gaudy-font-lock-keywords
			      )
			     t ; do not do string/comment highlighting
			     nil ; keywords are case sensitive.
			     ;; This puts _ as a word constituent,
			     ;; simplifying our keywords significantly
			     ((?_ . "w"))))
  (matlab-enable-block-highlighting 1)
  (if window-system (matlab-frame-init))
  (run-hooks 'matlab-mode-hook)
  (if matlab-vers-on-startup (matlab-show-version)))

;;; Utilities =================================================================

(defun matlab-show-version ()
  "Show the version number in the minibuffer."
  (interactive)
  (message "matlab-mode, version %s" matlab-mode-version))

(defun matlab-find-prev-line ()
  "Recurse backwards until a code line is found."
  (if (= -1 (forward-line -1)) nil
    (if (matlab-ltype-empty) (matlab-find-prev-line) t)))

(defun matlab-prev-line ()
  "Go to the previous line of code.  Return nil if not found."
  (interactive)
  (let ((old-point (point)))
    (if (matlab-find-prev-line) t (goto-char old-point) nil)))

(defun matlab-uniquafy-list (lst)
  "Return a list that is a subset of LST where all elements are unique."
  (let ((nlst nil))
    (while lst
      (if (and (car lst) (not (member (car lst) nlst)))
	  (setq nlst (cons (car lst) nlst)))
      (setq lst (cdr lst)))
    (nreverse nlst)))

; Aki Vehtari <Aki.Vehtari@hut.fi> recommends this: (19.29 required)
;(require 'backquote)
;(defmacro matlab-navigation-syntax (&rest body)
;  "Evaluate BODY with the matlab-mode-special-syntax-table"
;  '(let	((oldsyntax (syntax-table)))
;    (unwind-protect
;	(progn
;	  (set-syntax-table matlab-mode-special-syntax-table)
;	   ,@body)
;      (set-syntax-table oldsyntax))))

(defmacro matlab-navigation-syntax (&rest forms)
  "Set the current environment for syntax-navigation and execute FORMS."
  (list 'let '((oldsyntax (syntax-table)))
	 (list 'unwind-protect
		(list 'progn
		       '(set-syntax-table matlab-mode-special-syntax-table)
			(cons 'progn forms))
		'(set-syntax-table oldsyntax))))

(put 'matlab-navigation-syntax 'lisp-indent-function 0)
(add-hook 'edebug-setup-hook
	  (lambda ()
	    (def-edebug-spec matlab-navigation-syntax def-body)))

(defun matlab-valid-end-construct-p ()
  "Return non-nil if the end after point terminates a block.
Return nil if it is being used to dereference an array."
  (condition-case nil
      (save-restriction
	;; Restrict navigation only to the current command line
	(save-excursion
	  (matlab-beginning-of-command)
	  (narrow-to-region (point)
			    (progn (matlab-end-of-command) (point))))
	(save-excursion
	  ;; end of param list
	  (up-list 1)
	  ;; backup over the parens
	  (forward-sexp -1)
	  ;; If we get here, the END is inside parens, which is not a
	  ;; valid location for the END keyword.  As such it is being
	  ;; used to dereference array parameters
	  nil))
    ;; an error means the list navigation failed, which also means we are
    ;; at the top-level
    (error t)))

;;; Regexps for MATLAB language ===============================================

;; "-pre" means "partial regular expression"
;; "-if" and "-no-if" means "[no] Indent Function"

(defconst matlab-defun-regex "^\\s-*function\\>"
  "Regular expression defining the beginning of a Matlab function.")

(defconst matlab-block-beg-pre-if "function\\|for\\|while\\|if\\|switch\\|try"
  "Keywords which mark the beginning of an indented block.
Includes function.")

(defconst matlab-block-beg-pre-no-if "for\\|while\\|if\\|switch\\|try"
  "Keywords which mark the beginning of an indented block.
Excludes function.")

(defun matlab-block-beg-pre ()
  "Partial regular expression to recognize Matlab block-begin keywords."
  (if matlab-indent-function
      matlab-block-beg-pre-if
    matlab-block-beg-pre-no-if))

(defconst matlab-block-mid-pre
  "elseif\\|else\\|catch"
  "Partial regular expression to recognize Matlab mid-block keywords.")

(defconst matlab-block-end-pre-if
  "end\\(function\\)?\\|function"
  "Partial regular expression to recognize Matlab block-end keywords.")

(defconst matlab-block-end-pre-no-if
  "end"
  "Partial regular expression to recognize Matlab block-end keywords.")

(defun matlab-block-end-pre ()
  "Partial regular expression to recognize Matlab block-end keywords."
  (if matlab-indent-function
      matlab-block-end-pre-if
    matlab-block-end-pre-no-if))

;; Not used.
;;(defconst matlab-other-pre
;;  "function\\|return"
;;  "Partial regular express to recognize Matlab non-block keywords.")

(defconst matlab-endless-blocks
  "case\\|otherwise"
  "Keywords which initialize new blocks, but don't have explicit ends.
Thus, they are endless.  A new case or otherwise will end a previous
endless block, and and end will end this block, plus any outside normal
blocks.")

(defun matlab-block-re ()
  "Regular expression for keywords which begin Matlab blocks."
  (concat "\\(^\\|[;,]\\)\\s-*\\("
 	  (matlab-block-beg-pre) "\\|"
  	  matlab-block-mid-pre "\\|"
 	  (matlab-block-end-pre) "\\|"
 	  matlab-endless-blocks "\\)\\b"))
  
(defun matlab-block-scan-re ()
  "Expression used to scan over matching pairs of begin/ends."
  (concat "\\(^\\|[;,]\\)\\s-*\\("
 	  (matlab-block-beg-pre) "\\|"
 	  (matlab-block-end-pre) "\\)\\b"))

(defun matlab-block-beg-re ()
  "Expression used to find the beginning of a block."
  (concat "\\(" (matlab-block-beg-pre) "\\)"))

(defun matlab-block-mid-re ()
  "Expression used to find block center parts (like else)."
  (concat "\\(" matlab-block-mid-pre "\\)"))

(defun matlab-block-end-re ()
  "Expression used to end a block.  Usually just `end'."
  (concat "\\(" (matlab-block-end-pre) "\\)"))

(defun matlab-block-end-no-function-re ()
  "Expression representing and end if functions are excluded."
  (concat "\\<\\(" matlab-block-end-pre-no-if "\\)\\>"))

(defun matlab-endless-blocks-re ()
  "Expression of block starters that do not have associated ends."
  (concat "\\(" matlab-endless-blocks "\\)"))

(defconst matlab-cline-start-skip "[ \t]*%[ \t]*"
  "*The regular expression for skipping comment start.")

;;; Lists for matlab keywords =================================================

(defvar matlab-keywords-solo
  '("break" "case" "else" "elseif" "end" "for" "function" "if"
    "otherwise" "profile" "switch" "while")
  "Keywords that appear on a line by themselves.")
(defvar matlab-keywords-return
  '("acos" "acosh" "acot" "acoth" "acsch" "asech" "asin" "asinh"
    "atan" "atan2" "atanh" "cos" "cosh" "coth" "csc" "csch" "exp"
    "log" "log10" "log2" "sec" "sech" "sin" "sinh" "tanh"
    "abs" "sign" "sqrt" )
  "List of Matlab keywords that have return arguments.
This list still needs lots of help.")
(defvar matlab-keywords-boolean
  '("all" "any" "exist" "isempty" "isequal" "ishold" "isfinite" "isglobal"
    "isinf" "isletter" "islogical" "isnan" "isprime" "isreal" "isspace"
    "logical")
  "List of keywords that are typically used as boolean expressions.")

(defvar matlab-core-properties
  '("ButtonDownFcn" "Children" "Clipping" "CreateFcn" "DeleteFcn"
    "BusyAction" "HandleVisibility" "HitTest" "Interruptible"
    "Parent" "Selected" "SelectionHighlight" "Tag" "Type"
    "UIContextMenu" "UserData" "Visible")
  "List of properties belonging to all HG objects.")

(defvar matlab-property-lists
  '(("root" .
     ("CallbackObject" "Language" "CurrentFigure" "Diary" "DiaryFile"
      "Echo" "ErrorMessage" "Format" "FormatSpacing" "PointerLocation"
      "PointerWindow" "Profile" "ProfileFile" "ProfileCount"
      "ProfileInterval" "RecursionLimit" "ScreenDepth" "ScreenSize"
      "ShowHiddenHandles" "TerminalHideGraphCommand" "TerminalOneWindow"
      "TerminalDimensions" "TerminalProtocol" "TerminalShowGraphCommand"
      "Units" "AutomaticFileUpdates" ))
    ("axes" .
     ("AmbientLightColor" "Box" "CameraPosition" "CameraPositionMode"
      "CameraTarget" "CameraTargetMode" "CameraUpVector"
      "CameraUpVectorMode" "CameraViewAngle" "CameraViewAngleMode" "CLim"
      "CLimMode" "Color" "CurrentPoint" "ColorOrder" "DataAspectRatio"
      "DataAspectRatioMode" "DrawMode" "FontAngle" "FontName" "FontSize"
      "FontUnits" "FontWeight" "GridLineStyle" "Layer" "LineStyleOrder"
      "LineWidth" "NextPlot" "PlotBoxAspectRatio" "PlotBoxAspectRatioMode"
      "Projection" "Position" "TickLength" "TickDir" "TickDirMode" "Title"
      "Units" "View" "XColor" "XDir" "XGrid" "XLabel" "XAxisLocation" "XLim"
      "XLimMode" "XScale" "XTick" "XTickLabel" "XTickLabelMode" "XTickMode"
      "YColor" "YDir" "YGrid" "YLabel" "YAxisLocation" "YLim" "YLimMode"
      "YScale" "YTick" "YTickLabel" "YTickLabelMode" "YTickMode" "ZColor"
      "ZDir" "ZGrid" "ZLabel" "ZLim" "ZLimMode" "ZScale" "ZTick"
      "ZTickLabel" "ZTickLabelMode" "ZTickMode"))
    ("figure" .
     ("BackingStore" "CloseRequestFcn" "Color" "Colormap"
      "CurrentAxes" "CurrentCharacter" "CurrentObject" "CurrentPoint"
      "Dithermap" "DithermapMode" "FixedColors" "IntegerHandle"
      "InvertHardcopy" "KeyPressFcn" "MenuBar" "MinColormap" "Name"
      "NextPlot" "NumberTitle" "PaperUnits" "PaperOrientation"
      "PaperPosition" "PaperPositionMode" "PaperSize" "PaperType"
      "Pointer" "PointerShapeCData" "PointerShapeHotSpot" "Position"
      "Renderer" "RendererMode" "Resize" "ResizeFcn" "SelectionType"
      "ShareColors" "Units" "WindowButtonDownFcn"
      "WindowButtonMotionFcn" "WindowButtonUpFcn" "WindowStyle"))
    ("image" . ("CData" "CDataMapping" "EraseMode" "XData" "YData"))
    ("light" . ("Position" "Color" "Style"))
    ("line" .
     ("Color" "EraseMode" "LineStyle" "LineWidth" "Marker"
      "MarkerSize" "MarkerEdgeColor" "MarkerFaceColor" "XData" "YData"
      "ZData"))
    ("patch" .
     ("CData" "CDataMapping" "FaceVertexCData" "EdgeColor" "EraseMode"
      "FaceColor" "Faces" "LineStyle" "LineWidth" "Marker"
      "MarkerEdgeColor" "MarkerFaceColor" "MarkerSize" "Vertices"
      "XData" "YData" "ZData" "FaceLighting" "EdgeLighting"
      "BackFaceLighting" "AmbientStrength" "DiffuseStrength"
      "SpecularStrength" "SpecularExponent" "SpecularColorReflectance"
      "VertexNormals" "NormalMode"))
    ("surface" .
     ("CData" "CDataMapping" "EdgeColor" "EraseMode" "FaceColor"
      "LineStyle" "LineWidth" "Marker" "MarkerEdgeColor"
      "MarkerFaceColor" "MarkerSize" "MeshStyle" "XData" "YData"
      "ZData" "FaceLighting" "EdgeLighting" "BackFaceLighting"
      "AmbientStrength" "DiffuseStrength" "SpecularStrength"
      "SpecularExponent" "SpecularColorReflectance" "VertexNormals"
      "NormalMode"))
    ("text\\|title\\|xlabel\\|ylabel\\|zlabel" .
     ("Color" "EraseMode" "Editing" "Extent" "FontAngle" "FontName"
      "FontSize" "FontUnits" "FontWeight" "HorizontalAlignment"
      "Position" "Rotation" "String" "Units" "Interpreter"
      "VerticalAlignment"))
    ("uicontextmenu" . ("Callback"))
    ("uicontrol" .
     ("BackgroundColor" "Callback" "CData" "Enable" "Extent"
      "FontAngle" "FontName" "FontSize" "FontUnits" "FontWeight"
      "ForegroundColor" "HorizontalAlignment" "ListboxTop" "Max" "Min"
      "Position" "String" "Style" "SliderStep" "TooltipString" "Units"
      "Value"))
    ("uimenu" .
     ("Accelerator" "Callback" "Checked" "Enable" "ForegroundColor"
      "Label" "Position" "Separator"))
    ;; Flesh this out more later.
    ("uipushtool\\|uitoggletool\\|uitoolbar" .
     ("Cdata" "Callback" "Separator" "Visible"))
    )
  "List of property lists on a per object type basis.")

(defvar matlab-unknown-type-commands
  "[gs]et\\|findobj"
  "Expression for commands that have unknown types.")

(defun matlab-all-known-properties ()
  "Return a list of all properties."
  (let ((lst matlab-core-properties)
	(tl matlab-property-lists))
    (while tl
      (setq lst (append lst (cdr (car tl)))
	    tl (cdr tl)))
    (matlab-uniquafy-list lst)))

(defvar matlab-all-known-properties (matlab-all-known-properties)
  "List of all the known properties.")

(defmacro matlab-property-function ()
  "Regexp of all builtin functions that take property lists."
  '(let ((r matlab-unknown-type-commands)
	 (tl matlab-property-lists))
     (while tl
       (setq r (concat r "\\|" (car (car tl)))
	     tl (cdr tl)))
     r))

;;; Navigation ===============================================================

(defvar matlab-scan-on-screen-only nil
  "When this is set to non-nil, then forward/backward sexp stops off screen.
This is so the block highlighter doesn't gobble up lots of time when
a block is not terminated.")

(defun matlab-backward-sexp (&optional autoend noerror)
  "Go backwards one balanced set of Matlab expressions.
If optional AUTOEND, then pretend we are at an end.
If optional NOERROR, then we return t on success, and nil on failure."
  (interactive "P")
  (matlab-navigation-syntax
    (if (and (not autoend)
	     (save-excursion (backward-word 1)
			     (or (not
				  (and (looking-at
					(matlab-block-end-no-function-re))
				       (matlab-valid-end-construct-p)))
				 (matlab-cursor-in-string-or-comment))))
	;; Go backwards one simple expression
	(forward-sexp -1)
      ;; otherwise go backwards recursively across balanced expressions
      ;; backup over our end
      (if (not autoend) (forward-word -1))
      (let ((done nil) (start (point)) (returnme t))
	(while (and (not done)
		    (or (not matlab-scan-on-screen-only)
			(pos-visible-in-window-p)))
	  (if (re-search-backward (matlab-block-scan-re) nil t)
	      (progn
		(goto-char (match-beginning 2))
		(if (looking-at (matlab-block-end-no-function-re))
		    (if (or (matlab-cursor-in-string-or-comment)
			    (not (matlab-valid-end-construct-p)))
			nil
		      ;; we must skip the expression and keep searching
		      (forward-word 1)
		      (matlab-backward-sexp))
		  (if (not (matlab-cursor-in-string-or-comment))
		      (setq done t))))
	    (goto-char start)
	    (if noerror
		(setq returnme nil)
	      (error "Unstarted END construct"))))
	returnme))))
  
(defun matlab-forward-sexp ()
    "Go forward one balanced set of Matlab expressions."
  (interactive)
  (matlab-navigation-syntax
    ;; skip over preceeding whitespace
    (skip-chars-forward " \t\n;")
    (if (or (not (looking-at (concat "\\("
				     (matlab-block-beg-pre)
				     "\\)\\>")))
	    (matlab-cursor-in-string-or-comment))
	;; Go forwards one simple expression
	(forward-sexp 1)
      ;; otherwise go forwards recursively across balanced expressions
      (forward-word 1)
      (let ((done nil) (s nil)
	    (expr-scan (matlab-block-scan-re))
	    (expr-look (matlab-block-beg-pre)))
	(while (and (not done)
		    (setq s (re-search-forward expr-scan nil t))
		    (or (not matlab-scan-on-screen-only)
			(pos-visible-in-window-p)))
	  (goto-char (match-beginning 2))
	  (if (looking-at expr-look)
	      (if (matlab-cursor-in-string-or-comment)
		  (forward-word 1)
		;; we must skip the expression and keep searching
		(matlab-forward-sexp))
	    (forward-word 1)
	    (if (and (not (matlab-cursor-in-string-or-comment))
		     (matlab-valid-end-construct-p))
		(setq done t))))
	(if (not s) (error "Unterminated block"))))))

(defun matlab-beginning-of-defun ()
  "Go to the beginning of the current function."
  (interactive)
  (or (re-search-backward matlab-defun-regex nil t)
      (goto-char (point-min))))

(defun matlab-end-of-defun ()
  "Go to the end of the current function."
  (interactive)
  (or (progn
	(if (looking-at matlab-defun-regex) (goto-char (match-end 0)))
	(if (re-search-forward matlab-defun-regex nil t)
	    (progn (forward-line -1)
		   t)))
      (goto-char (point-max))))

(defun matlab-beginning-of-command ()
  "Go to the beginning of an M command.
Travels across continuations."
  (interactive)
  (beginning-of-line)
  (while (progn (forward-line -1) (and (matlab-lattr-cont) (not (bobp)))))
  (forward-line 1)
  (back-to-indentation))

(defun matlab-end-of-command ()
  "Go to the end of an M command.
Travels across continuations."
  (interactive)
  (while (matlab-lattr-cont)
    (forward-line 1))
  (end-of-line))

;;; Line types and attributes =================================================

(defun matlab-ltype-empty ()		; blank line
  "Return t if current line is empty."
  (save-excursion
    (beginning-of-line)
    (looking-at "^[ \t]*$")))

(defun matlab-ltype-comm ()		; comment line
  "Return t if current line is a MATLAB comment line."
  (save-excursion
    (beginning-of-line)
    (looking-at "[ \t]*%.*$")))

(defun matlab-ltype-code ()		; line of code
  "Return t if current line is a MATLAB code line."
  (and (not (matlab-ltype-empty)) (not (matlab-ltype-comm))))

(defun matlab-lattr-comm ()		; line has comment
  "Return t if current line contain a comment."
  (save-excursion (matlab-comment-on-line)))

(defun matlab-lattr-cont ()		; line has continuation
  "Return non-nil if current line ends in ... and optional comment."
  (save-excursion
    (beginning-of-line)
    (and (re-search-forward "[^ \t.][ \t]*\\.\\.+[ \t]*\\(%.*\\)?$"
			    (matlab-point-at-eol) t)
	 (progn (goto-char (match-beginning 0))
		(not (matlab-cursor-in-comment))))))

(defun matlab-lattr-semantics (&optional prefix)
  "Return the semantics of the current position.
Values are nil 'solo, 'value, and 'boolean.  Boolean is a subset of
value.  nil means there is no semantic content (ie, string or comment.)
If optional PREFIX, then return 'solo if that is the only thing on the
line."
  (cond ;((matlab-cursor-in-string-or-comment)
	 ;nil)
	((or (matlab-ltype-empty)
	     (and prefix (save-excursion
			   (beginning-of-line)
			   (looking-at (concat "\\s-*" prefix "\\s-*$")))))
	 'solo)
	((save-excursion
	   (matlab-beginning-of-command)
	   (looking-at "\\s-*\\(if\\|elseif\\|while\\)\\>"))
	 'boolean)
	((save-excursion
	   (matlab-beginning-of-command)
	   (looking-at (concat "\\s-*\\(" (matlab-property-function)
			       "\\)\\>")))
	 'property)
	(t
	 'value)))

(defun matlab-function-called-at-point ()
  "Return a string representing the function called nearby point."
  (save-excursion
    (beginning-of-line)
    (cond ((looking-at "\\s-*\\([a-zA-Z]\\w+\\)[^=][^=]")
	   (match-string 1))
	  ((and (re-search-forward "=" (matlab-point-at-eol) t)
		(looking-at "\\s-*\\([a-zA-Z]\\w+\\)\\s-*[^=]"))
	   (match-string 1))
	  (t nil))))

(defun matlab-cursor-in-string-or-comment ()
  "Return t if the cursor is in a valid Matlab comment or string."
  ;; comment and string depend on each other.  Here is one test
  ;; that does both.
  (save-restriction
    (narrow-to-region (matlab-point-at-bol) (matlab-point-at-eol))
    (let ((p (1+ (point)))
	  (returnme nil)
	  (sregex (concat matlab-string-start-regexp "'")))
      (save-excursion
	(goto-char (point-min))
	(while (and (re-search-forward "'\\|%\\|\\.\\.\\." nil t)
		    (<= (point) p))
	  (if (or (= ?% (preceding-char))
		  (= ?. (preceding-char)))
	      ;; Here we are in a comment for the rest of it.
	      (progn
		(goto-char p)
		(setq returnme t))
	    ;; Here, we could be a string start, or transpose...
	    (if (or (= (current-column) 1)
		    (save-excursion (forward-char -2)
				    (looking-at sregex)))
		;; a valid string start, find the end
		(let ((f (re-search-forward matlab-string-end-regexp nil t)))
		  (if f
		      (setq returnme (> (point) p))
		    (setq returnme t)))
	      ;; Ooops, a transpose, keep going.
	      ))))
      returnme)))

(defun matlab-cursor-in-comment ()
  "Return t if the cursor is in a valid Matlab comment."
  (save-restriction
    (narrow-to-region (matlab-point-at-bol) (matlab-point-at-eol))
    (save-excursion
      (let ((prev-match nil))
      (while (and (re-search-backward "%\\|\\.\\.\\.+" nil t)
		  (not (matlab-cursor-in-string)))
	(setq prev-match (point)))
      (if (and prev-match (matlab-cursor-in-string))
	  (goto-char prev-match))
      (and (looking-at "%\\|\\.\\.\\.")
	   (not (matlab-cursor-in-string)))))))

(defun matlab-cursor-in-string (&optional incomplete)
  "Return t if the cursor is in a valid Matlab string.
If the optional argument INCOMPLETE is non-nil, then return t if we
are in what could be a an incomplete string."
  (save-restriction
    (narrow-to-region (matlab-point-at-bol) (matlab-point-at-eol))
    (let ((p (1+ (point)))
	  (returnme nil)
	  (sregex (concat matlab-string-start-regexp "'")))
      (save-excursion
	;; Comment hunters need strings to not call the comment
	;; identifiers.  Thus, this routines must be savvy of comments
	;; without recursing to them.
	(goto-char (point-min))
	(while (and (re-search-forward "'\\|%\\|\\.\\.\\." nil t)
		    (<= (point) p))
	  (if (or (= ?% (preceding-char))
		  (= ?. (preceding-char)))
	      ;; Here we are in a comment for the rest of it.
	      ;; thus returnme is a force-false.
	      (goto-char p)
	    ;; Here, we could be in a string start, or transpose...
	    (if (or (= (current-column) 1)
		    (save-excursion (forward-char -2)
				    (looking-at sregex)))
		;; a valid string start, find the end
		(let ((f (re-search-forward matlab-string-end-regexp nil t)))
		  (if (and (not f) incomplete)
		      (setq returnme t)
		    (setq returnme (> (point) p))))
	      ;; Ooops, a transpose, keep going.
	      ))))
      returnme)))

(defun matlab-comment-on-line ()
  "Place the cursor on the beginning of a valid comment on this line.
If there isn't one, then return nil, point otherwise."
  (let ((eol (matlab-point-at-eol))
	(p (point))
	(signal-error-on-buffer-boundary nil))
    (beginning-of-line)
    (while (and (re-search-forward "%" eol t)
		(matlab-cursor-in-string)))
    (forward-char -1)
    (if (looking-at "%")
	(point)
      (goto-char p)
      nil)))

;;; Indent functions ==========================================================

(defun matlab-indent-line ()
  "Indent a line in `matlab-mode'."
  (interactive)
  (let ((i (matlab-calc-indent))
	(c (current-column)))
    (save-excursion
      (back-to-indentation)
      (if (= i (current-column))
	  nil
	(beginning-of-line)
	(delete-horizontal-space)
	(indent-to (matlab-calc-indent)))
      ;; If line contains a comment, format it.
      (if () (if (matlab-lattr-comm) (matlab-comment))))
    (if (<= c i) (move-to-column i))))

(defun matlab-calc-indent ()
  "Return the appropriate indentation for this line as an integer."
  (interactive)
  (let ((indent 0))
    (save-excursion
      (if (matlab-prev-line)
	  (setq indent (+ (current-indentation) (matlab-add-to-next)))))
    (setq indent (+ indent (matlab-add-from-prev)))
    indent))

(defun matlab-add-to-next ()
  (car (cdr (matlab-calc-deltas))))

(defun matlab-add-from-prev ()
  (car (matlab-calc-deltas)))

;; This appears after the above.  This is the tried-and-true version.
(defun matlab-calc-deltas ()
  "Return the list (ADD-FROM-PREV ADD-TO-NEXT).
ADD-FROM-PREV is the amount of indentation added from the previous line of
code.  ADD-TO-NEXT is the amount of indentation to add the the next
line of code based on it's textual content."
  (let ((add-from-prev 0) (add-to-next 0) eol)
    (if (matlab-ltype-comm)
	(if matlab-indent-function
	    (save-excursion
	      (beginning-of-line)
	      (if (looking-at "^[ \t]*%[ \t]*endfunction")
		  (list (- matlab-indent-level) 0)
		;; skip over all the following comments
		(while (and (not (eobp))
			    (or (matlab-ltype-comm)
				(matlab-ltype-empty)))
		  (forward-line 1)
		  (end-of-line))
		;; Are we looking at a function?
		(beginning-of-line)
		(if (looking-at matlab-defun-regex)
		    (list (- matlab-indent-level) 0)
		  (list 0 0))))
	  (list 0 0))
      (save-excursion
	(matlab-navigation-syntax
	  (setq eol (matlab-point-at-eol))
	  ;; indentation for control structures
	  (beginning-of-line)
	  (while (re-search-forward (matlab-block-re) eol t)
	    (save-excursion
	      (goto-char (match-beginning 2))
	      (if (looking-at (matlab-block-beg-re))
		  (progn
		    (setq add-to-next (+ add-to-next matlab-indent-level))
		    ;; In some circumstances a block begin is also a block
		    ;; end, notably, FUNCTION will mark the end of a previous
		    ;; FUNCTION.  Theoretically when looking at a FUNCTION
		    ;; line I should verify backwards that we are also ending
		    ;; a function, but that might be too pesky.
		    (if (looking-at (matlab-block-end-re))
			(setq add-from-prev
			      (- add-from-prev matlab-indent-level))))
		(if (> add-to-next 0)
		    (setq add-to-next (- add-to-next matlab-indent-level))
		  ;; This assumes some sort of END at this point.  Lets
		  ;; make sure it is a valid end:
		  (if (matlab-valid-end-construct-p)
		      (setq add-from-prev
			    (- add-from-prev matlab-indent-level))))
		(if (looking-at (matlab-endless-blocks-re))
		    ;; With the introduction of switch statements, our current
		    ;; indentation is no-longer indicative of the last opened
		    ;; block statement.  We must use the specialized forward/
		    ;; backward sexp to navigate over intervening blocks of
		    ;; code to learn our true indentation level.
		    (save-excursion
		      (let ((p (point)))
			(setq add-to-next (+ add-to-next matlab-indent-level))
			;; Ok, the fun is over, now for some unpleasant scanning
			(matlab-backward-sexp t)
			(if (and
			     (re-search-forward (matlab-endless-blocks-re)
						nil t)
			     (< p (point)))
			    (setq add-from-prev
				  (+ add-from-prev matlab-indent-level))))))
		(if (looking-at (matlab-block-end-re))
		    (save-excursion
		      (forward-word 1)
		      (matlab-backward-sexp)
		      (if (looking-at "switch")
			  (setq add-from-prev
				(- add-from-prev matlab-indent-level)))))
		(if (looking-at (matlab-block-mid-re))
		    (setq add-to-next (+ add-to-next matlab-indent-level))))))
	  ;; indentation for matrix expressions
	  (beginning-of-line)
	  (while (re-search-forward "[][{}]" eol t)
	    (save-excursion
	      (goto-char (match-beginning 0))
	      (if (matlab-cursor-in-string-or-comment)
		  nil
		(if (looking-at "[[{]")
		    (setq add-to-next (+ add-to-next matlab-indent-level))
		  (setq add-to-next (- add-to-next matlab-indent-level))))))
	  ;; continuation lines
	  (if (matlab-lattr-cont)
	      (save-excursion
		(if (= 0 (forward-line -1))
		    (if (matlab-lattr-cont)
			()
		      (setq add-to-next (+ add-to-next matlab-cont-level)))
		  (setq add-to-next (+ add-to-next matlab-cont-level))))
	    (save-excursion
	      (if (= 0 (forward-line -1))
		  (if (matlab-ltype-comm) ()
		    (if (matlab-lattr-cont)
			(setq add-to-next (- add-to-next matlab-cont-level)))))))
	  )
	(list add-from-prev add-to-next)))))

;;; The return key ============================================================

(defcustom matlab-return-function 'matlab-indent-end-before-ret
  "Function to handle return key.
Must be one of:
    'matlab-plain-ret
    'matlab-indent-after-ret
    'matlab-indent-end-before-ret
    'matlab-indent-before-ret"
  :group 'matlab
  :type '(choice (function-item matlab-plain-ret)
		 (function-item matlab-indent-after-ret)
		 (function-item matlab-indent-end-before-ret)
		 (function-item matlab-indent-before-ret)))

(defun matlab-return ()
  "Handle carriage return in `matlab-mode'."
  (interactive)
  (funcall matlab-return-function))

(defun matlab-plain-ret ()
  "Vanilla new line."
  (interactive)
  (newline))
  
(defun matlab-indent-after-ret ()
  "Indent after new line."
  (interactive)
  (newline)
  (matlab-indent-line))

(defun matlab-indent-end-before-ret ()
  "Indent line if block end, start new line, and indent again."
  (interactive)
  (if (save-excursion
	(beginning-of-line)
	(looking-at "[ \t]*\\(catch\\|elseif\\|else\\|end\\|case\\|otherwise\\)\\b"))
      (condition-case nil
	  (matlab-indent-line)
	(error nil)))
  (newline)
  (matlab-indent-line))

(defun matlab-indent-before-ret ()
  "Indent line, start new line, and indent again."
  (interactive)
  (matlab-indent-line)
  (newline)
  (matlab-indent-line))

(defun matlab-linefeed ()
  "Handle line feed in `matlab-mode'.
Has effect of `matlab-return' with (not matlab-indent-before-return)."
  (interactive)
  (matlab-indent-line)
  (newline)
  (matlab-indent-line))

(defun matlab-comment-return ()
  "Handle carriage return for Matlab comment line."
  (interactive)
  (cond
   ((matlab-ltype-comm)
    (matlab-set-comm-fill-prefix) (newline) (insert fill-prefix)
    (matlab-reset-fill-prefix) (matlab-indent-line))
   ((matlab-lattr-comm)
    (newline) (indent-to matlab-comment-column)
    (insert matlab-comment-on-line-s))
   (t
    (newline) (matlab-comment) (matlab-indent-line))))

(defun matlab-comm-from-prev ()
  "If the previous line is a comment-line then set up a comment on this line."
  (save-excursion
    ;; If the previous line is a comment-line then set the fill prefix from
    ;; the previous line and fill this line.
    (if (and (= 0 (forward-line -1)) (matlab-ltype-comm))
	(progn
	  (matlab-set-comm-fill-prefix)
	  (forward-line 1) (beginning-of-line)
	  (delete-horizontal-space)
	  (if (looking-at "%") (delete-char 1))
	  (delete-horizontal-space)
	  (insert fill-prefix)
	  (matlab-reset-fill-prefix)))))

;;; Comment management========================================================

(defun matlab-comment ()
  "Add a comment to the current line."
  (interactive)
  (cond ((matlab-ltype-empty)		; empty line
	 (matlab-comm-from-prev)
	 (if (matlab-lattr-comm)
	     (skip-chars-forward " \t%")
	   (insert matlab-comment-line-s)
	   (matlab-indent-line)))
	((matlab-ltype-comm)		; comment line
	 (matlab-comm-from-prev)
	 (skip-chars-forward " \t%"))
	((matlab-lattr-comm)		; code line w/ comment
	 (beginning-of-line)
	 (re-search-forward "[^%]%[ \t]")
	 (forward-char -2)
	 (if (< (current-column) matlab-comment-column)
	     (indent-to matlab-comment-column))
	 (skip-chars-forward "% \t"))
	(t				; code line w/o comment
	 (end-of-line)
	 (re-search-backward "[^ \t\n^]" 0 t)
	 (forward-char)
	 (delete-horizontal-space)
	 (if (< (current-column) matlab-comment-column)
	     (indent-to matlab-comment-column)
	   (insert " "))
	 (insert matlab-comment-on-line-s))))

(defun matlab-comment-indent ()
  "Indent a comment line in `matlab-mode'."
  (matlab-calc-indent))

(defun matlab-comment-region (beg-region end-region arg)
  "Comments every line in the region.
Puts `matlab-comment-region-s' at the beginning of every line in the region.
BEG-REGION and END-REGION are arguments which specify the region boundaries.
With non-nil ARG, uncomments the region."
  (interactive "*r\nP")
  (let ((end-region-mark (make-marker)) (save-point (point-marker)))
    (set-marker end-region-mark end-region)
    (goto-char beg-region)
    (beginning-of-line)
    (if (not arg)			;comment the region
	(progn (insert matlab-comment-region-s)
	       (while (and  (= (forward-line 1) 0)
			    (< (point) end-region-mark))
		 (insert matlab-comment-region-s)))
      (let ((com (regexp-quote matlab-comment-region-s))) ;uncomment the region
	(if (looking-at com)
	    (delete-region (point) (match-end 0)))
	(while (and  (= (forward-line 1) 0)
		     (< (point) end-region-mark))
	  (if (looking-at com)
	      (delete-region (point) (match-end 0))))))
    (goto-char save-point)
    (set-marker end-region-mark nil)
    (set-marker save-point nil)))

;;; Filling ===================================================================

(defun matlab-set-comm-fill-prefix ()
  "Set the `fill-prefix' for the current (comment) line."
  (interactive)
  (setq fill-prefix
	(save-excursion
	  (beginning-of-line)
	  (buffer-substring
	   (point)
	   (progn (re-search-forward "[ \t]*%[ \t]+") (point))))))

(defun matlab-set-comm-fill-prefix-post-code ()
  "Set the `fill-prefix' for the current post-code comment line."
  (interactive)
  (save-excursion
    (end-of-line)
    (let ((bol (matlab-point-at-bol))
	  (cc 0))
      (while (and (re-search-backward "%[ \t]*" bol t)
		  (save-match-data (matlab-cursor-in-string))))
      (if (match-string 0)
	  (setq cc (current-column)))
      (setq fill-prefix (concat (make-string cc ?\ ) (match-string 0))))))

(defun matlab-set-code-fill-prefix ()
  "Set the `fill-prefix' for the current code line."
  (setq fill-prefix
	(save-excursion
	  (beginning-of-line)
	  (buffer-substring
	   (point)
	   (progn (re-search-forward "[ \t]*") (point))))))

(defun matlab-reset-fill-prefix ()
  "Reset the `fill-prefix'."
  (setq fill-prefix nil))

(defun matlab-auto-fill ()
  "Do auto filling.
Set variable `auto-fill-function' to this symbol to enable Matlab style auto
filling which will automatically insert `...' and the end of a line."
  (interactive)
  (let ((fill-prefix fill-prefix) ;; safe way of modifying fill-prefix.
	(fill-column (- fill-column
			(if matlab-fill-count-ellipsis-flag
			    (save-excursion
			      (move-to-column fill-column)
			      (if (not (bobp))
				  (forward-char -1))
			      (if (matlab-cursor-in-string 'incomplete)
				  4 3))
			  0))))
    (if (> (current-column) fill-column)
	(cond
	 ((matlab-ltype-comm)
	  ;; If the whole line is a comment, do this.
	  (matlab-set-comm-fill-prefix) (do-auto-fill)
	  (matlab-reset-fill-prefix))
	 ((and
	   (and (matlab-ltype-code) (not (matlab-lattr-comm)))
	   matlab-fill-code)
	  ;; If we are on a code line, we ellipsify before we fill.
	  (let ((m (make-marker)))
	    (move-marker m (point))
	    (set-marker-insertion-type m t)
	    (while (> (current-column) fill-column) (forward-char -1))
	    (re-search-backward "[ \t]+")
	    (while (and matlab-fill-strings-flag
			(matlab-cursor-in-string)
			(re-search-forward "[ \t]+" (matlab-point-at-eol) t)))
	    (if (not (matlab-cursor-in-string 'incomplete))
		(progn
		  (delete-horizontal-space)
		  (insert " ...\n")
		  (matlab-indent-line))
	      ;; we are guaranteed to be in an incomplete string.
	      (if matlab-fill-strings-flag
		  (let ((pos (point))
			(pos2 nil))
		    (while (and (re-search-backward "'" nil t)
				(progn (forward-char -1)
				       (looking-at "''"))))
		    (setq pos2 (point))
		    (if (not (looking-at "\\["))
			(progn
			  (skip-chars-backward " \t")
			  (forward-char -1)))
		    (if (looking-at "\\[")
			(goto-char pos)
		      (goto-char pos2)
		      (forward-char 1)
		      (insert "[")
		      (goto-char pos)
		      (forward-char 1))
		    (delete-horizontal-space)
		    (insert "' ...\n")
		    (matlab-indent-line)
		    (insert "' "))))
	    (goto-char m)))
	 ((matlab-cursor-in-comment)
	  ;; If we are in a comment at the end of a statement
	  (matlab-set-comm-fill-prefix-post-code) (do-auto-fill)
	  (matlab-reset-fill-prefix))
	 ))))

(defun matlab-join-comment-lines ()
  "Join current comment line to the next comment line."
  ;; New w/ V2.0: This used to join the previous line, but I could find
  ;; no editors that had a "join" that did that.  I modified join to have
  ;; a behaviour I thought more inline with other editors.
  (interactive)
  (end-of-line)
  (if (looking-at "\n[ \t]*%")
      (replace-match " " t t nil)
    (error "No following comment to join with")))

(defun matlab-wrap-line () nil)

(defun matlab-fill-region (beg-region end-region &optional justify-flag)
  "Fill the region between BEG-REGION and END-REGION.
Non-nil JUSTIFY-FLAG means justify comment lines as well."
  (interactive "*r\nP")
  (let ((end-reg-mk (make-marker)))
    (set-marker end-reg-mk end-region)
    (goto-char beg-region)
    (beginning-of-line)
    (while (< (save-excursion (forward-line 1) (point)) end-reg-mk)
      (if (save-excursion (= (forward-line 1) 0))
	  (progn
	    (cond
	     ((matlab-ltype-comm)
	      (while (matlab-fill-comment-line))
	      (if justify-flag (matlab-justify-comment-line))))
	    (forward-line 1))))))

(defun matlab-fill-comment-line (&optional justify)
  "Fill the current comment line.
With optional argument, JUSTIFY the comment as well."
  (interactive)
  (if (not (matlab-comment-on-line))
      (error "No comment to fill"))
  (beginning-of-line)
  ;; First, find the beginning of this comment...
  (while (and (looking-at matlab-cline-start-skip)
	      (not (bobp)))
    (forward-line -1)
    (beginning-of-line))
  (if (not (looking-at matlab-cline-start-skip))
      (forward-line 1))
  ;; Now scan to the end of this comment so we have our outer bounds,
  ;; and narrow to that region.
  (save-restriction
    (narrow-to-region (point)
		      (save-excursion
			(while (and (looking-at matlab-cline-start-skip)
				    (not (save-excursion (end-of-line) (eobp))))
			  (forward-line 1)
			  (beginning-of-line))
			(if (not (looking-at matlab-cline-start-skip))
			    (forward-line -1))
			(end-of-line)
			(point)))
    ;; Find the fill prefix...
    (matlab-comment-on-line)
    (looking-at "%[ \t]*")
    (let ((fill-prefix (concat (make-string (current-column) ? )
			       (match-string 0))))
      (fill-region (point-min) (point-max) justify))))

(defun matlab-justify-line ()
  "Delete space on end of line and justify."
  (interactive)
  (save-excursion
    (end-of-line)
    (delete-horizontal-space)
    (justify-current-line)))

(defun matlab-justify-comment-line ()
  "Add spaces to comment line point is in, so it ends at `fill-column'."
  (interactive)
  (save-excursion
    (save-restriction
      (let (ncols beg)
	(beginning-of-line)
	(forward-char (length fill-prefix))
	(skip-chars-forward " \t")
	(setq beg (point))
	(end-of-line)
	(narrow-to-region beg (point))
	(goto-char beg)
	(while (re-search-forward "   *" nil t)
	  (delete-region
	   (+ (match-beginning 0)
	      (if (save-excursion
		    (skip-chars-backward " ])\"'")
		    (memq (preceding-char) '(?. ?? ?!)))
		  2 1))
	   (match-end 0)))
	(goto-char beg)
	(while (re-search-forward "[.?!][])""']*\n" nil t)
	  (forward-char -1)
	  (insert " "))
	(goto-char (point-max))
	(setq ncols (- fill-column (current-column)))
	(if (search-backward " " nil t)
	    (while (> ncols 0)
	      (let ((nmove (+ 3 (% (random) 3))))
		(while (> nmove 0)
		  (or (search-backward " " nil t)
		      (progn
			(goto-char (point-max))
			(search-backward " ")))
		  (skip-chars-backward " ")
		  (setq nmove (1- nmove))))
	      (insert " ")
	      (skip-chars-backward " ")
	      (setq ncols (1- ncols))))))))

(defun matlab-fill-paragraph (arg)
  "When in a comment, fill the current paragraph.
Paragraphs are always assumed to be in a comment.
ARG is passed to `fill-paragraph' and will justify the text."
  (interactive "P")
  (cond ((or (matlab-ltype-comm)
	     (matlab-cursor-in-comment))
	 ;; We are in a comment, lets fill the paragraph with some
	 ;; nice regular expressions.
	 (let ((paragraph-separate "%[a-zA-Z]\\|%[ \t]*$\\|[ \t]*$")
	       (paragraph-start "%[a-zA-Z]\\|%[ \t]*$\\|[ \t]*$")
	       (paragraph-ignore-fill-prefix nil)
	       (fill-prefix nil))
	   (matlab-set-comm-fill-prefix)
	   (fill-paragraph arg)))
	(t
	 (message "Paragraph Fill not supported in this context."))))

;;; Semantic text insertion ===================================================

(defun matlab-find-recent-variable-list (prefix)
  "Return a list of most recent variables starting with PREFIX as a string.
Reverse searches for the following are done first:
  1) Assignment
  2) if|for|while|switch <var>
  3) global variables
  4) function arguments.
All elements are saved in a list, which is then uniqafied.
If NEXT is non-nil, then the next element from the saved list is used.
If the list is empty, then searches continue backwards through the code."
  (matlab-navigation-syntax
    (let* ((bounds (save-excursion
		     (if (re-search-backward "^\\s-*function\\>" nil t)
			 (match-beginning 0) (point-min))))
	   (syms
	    (append
	     (save-excursion
	       (let ((lst nil))
		 (while (and
			 (re-search-backward
			  (concat "^\\s-*\\(" prefix "\\w+\\)\\s-*=")
			  bounds t)
			 (< (length lst) 10))
		   (setq lst (cons (match-string 1) lst)))
		 (nreverse lst)))
	     (save-excursion
	       (let ((lst nil))
		 (while (and (re-search-backward
			      (concat "\\<\\(" matlab-block-beg-pre-no-if
				      "\\)\\s-+(?\\s-*\\(" prefix
				      "\\w+\\)\\>")
			      bounds t)
			     (< (length lst) 10))
		   (setq lst (cons (match-string 2) lst)))
		 (nreverse lst)))
	     (save-excursion
	       (if (re-search-backward "^\\s-*global\\s-+" bounds t)
		   (let ((lst nil) m e)
		     (goto-char (match-end 0))
		     (while (looking-at "\\(\\w+\\)\\([ \t]+\\|$\\)")
		       (setq m (match-string 1)
			     e (match-end 0))
		       (if (equal 0 (string-match prefix m))
			   (setq lst (cons m lst)))
		       (goto-char e))
		     (nreverse lst))))
	     (save-excursion
	       (if (and (re-search-backward "^\\s-*function\\>" bounds t)
			(re-search-forward "\\<\\(\\w+\\)("
					   (matlab-point-at-eol) t))
		   (let ((lst nil) m e)
		     (while (looking-at "\\(\\w+\\)\\s-*[,)]\\s-*")
		       (setq m (match-string 1)
			     e (match-end 0))
		       (if (equal 0 (string-match prefix m))
			   (setq lst (cons m lst)))
		       (goto-char e))
		     (nreverse lst))))))
	   (fl nil))
      (while syms
	(if (car syms) (setq fl (cons (car syms) fl)))
	(setq syms (cdr syms)))
      (matlab-uniquafy-list (nreverse fl)))))

(defvar matlab-most-recent-variable-list nil
  "Maintained by `matlab-find-recent-variable'.")

(defun matlab-find-recent-variable (prefix &optional next)
  "Return the most recently used variable starting with PREFIX as a string.
See `matlab-find-recent-variable-list' for details.
In NEXT is non-nil, than continue through the list of elements."
  (if next
      (let ((next (car matlab-most-recent-variable-list)))
	(setq matlab-most-recent-variable-list
	      (cdr matlab-most-recent-variable-list))
	next)
    (let ((syms (matlab-find-recent-variable-list prefix))
	  (first nil))
      (if (eq matlab-completion-technique 'complete)
	  syms
	(setq first (car syms))
	(setq matlab-most-recent-variable-list (cdr syms))
	first))))

(defun matlab-find-user-functions-list (prefix)
  "Return a list of user defined functions that match PREFIX."
  (matlab-navigation-syntax
    (let ((syms
	   (append
	    (save-excursion
	      (goto-char (point-min))
	      (let ((lst nil))
		(while (re-search-forward "^\\s-*function\\>" nil t)
		  (if (re-search-forward
		       (concat "\\(" prefix "\\w+\\)\\s-*\\($\\|(\\)")
		       (matlab-point-at-eol) t)
		      (setq lst (cons (match-string 1) lst))))
		(nreverse lst)))
	    (let ((lst nil)
		  (files (directory-files
			  default-directory nil
			  (concat "^" prefix
				  "[a-zA-Z][a-zA-Z0-9]_+\\.m$"))))
	      (while files
		(setq lst (cons (progn (string-match "\\.m" (car files))
				       (substring (car files) 0
						  (match-beginning 0)))
				lst)
		      files (cdr files)))
	      lst)))
	  (fl nil))
      (while syms
	(if (car syms) (setq fl (cons (car syms) fl)))
	(setq syms (cdr syms)))
      (matlab-uniquafy-list (nreverse fl)))))

(defvar matlab-user-function-list nil
  "Maintained by `matlab-find-user-functions'.")

(defun matlab-find-user-functions (prefix &optional next)
  "Return a user function that match PREFIX and return it.
If optional argument NEXT is non-nil, then return the next found
object."
  (if next
      (let ((next (car matlab-user-function-list)))
	(setq matlab-user-function-list (cdr matlab-user-function-list))
	next)
    (let ((syms (matlab-find-user-functions-list prefix))
	  (first nil))
      (if (eq matlab-completion-technique 'complete)
	  syms
	(setq first (car syms))
	(setq matlab-user-function-list (cdr syms))
	first))))

(defvar matlab-generic-list-placeholder nil
  "Maintained by `matalb-generic-list-expand'.
Holds sub-lists of symbols left to be expanded.")

(defun matlab-generic-list-expand (list prefix &optional next)
  "Return an element from LIST that start with PREFIX.
If optional NEXT argument is non nil, then the next element in the
list is used.  nil is returned if there are not matches."
  (if next
      (let ((next (car matlab-generic-list-placeholder)))
	(setq matlab-generic-list-placeholder
	      (cdr matlab-generic-list-placeholder))
	next)
    (let ((re (concat "^" (regexp-quote prefix)))
	  (first nil)
	  (fl nil))
      (while list
	(if (string-match re (car list))
	    (setq fl (cons (car list) fl)))
	(setq list (cdr list)))
      (setq fl (nreverse fl))
      (if (eq matlab-completion-technique 'complete)
	  fl
	(setq first (car fl))
	(setq matlab-generic-list-placeholder (cdr fl))
	first))))

(defun matlab-solo-completions (prefix &optional next)
  "Return PREFIX matching elements for solo symbols.
If NEXT then the next patch from the list is used."
  (matlab-generic-list-expand matlab-keywords-solo prefix next))

(defun matlab-value-completions (prefix &optional next)
  "Return PREFIX matching elements for value symbols.
If NEXT then the next patch from the list is used."
  (matlab-generic-list-expand matlab-keywords-return prefix next))

(defun matlab-boolean-completions (prefix &optional next)
  "Return PREFIX matching elements for boolean symbols.
If NEXT then the next patch from the list is used."
  (matlab-generic-list-expand matlab-keywords-boolean prefix next))
 
(defun matlab-property-completions (prefix &optional next)
  "Return PREFIX matching elements for property names in strings.
If NEXT then the next property from the list is used."
  (let ((f (matlab-function-called-at-point))
	(lst matlab-property-lists)
	(foundlst nil)
	(expandto nil))
    ;; Look for this function.  If it is a known function then we
    ;; can now use a subset of available properties!
    (while (and lst (not foundlst))
      (if (string= (car (car lst)) f)
	  (setq foundlst (cdr (car lst))))
      (setq lst (cdr lst)))
    (if foundlst
	(setq foundlst (append foundlst matlab-core-properties))
      (setq foundlst matlab-all-known-properties))
    (setq expandto (matlab-generic-list-expand foundlst prefix next))
    ;; This looks to see if we have a singular completion.  If so,
    ;; then return it, and also append the "'" to the end.
    (cond ((and (listp expandto) (= (length expandto) 1))
	   (setq expandto (list (concat (car expandto) "'"))))
	  ((stringp expandto)
	   (setq expandto (concat expandto "'"))))
    expandto))

(defvar matlab-last-prefix nil
  "Maintained by `matlab-complete-symbol'.
The prefix used for the first completion command.")
(defvar matlab-last-semantic nil
  "Maintained by `matlab-complete-symbol'.
The last type of semantic used while completing things.")
(defvar matlab-completion-search-state nil
  "List of searching things we will be doing.")

(defun matlab-complete-symbol (&optional arg)
  "Complete a partially typed symbol in a Matlab mode buffer.
If the previously entered command was also `matlab-complete-symbol'
then undo the last completion, and find a new one.
  The types of symbols tried are based on the semantics of the current
cursor position.  There are two types of symbols.  For example, if the
cursor is in an if statement, boolean style functions and symbols are
tried first.  If the line is blank, then flow control, or high level
functions are tried first.
  The completion technique is controlled with `matlab-completion-technique'
It defaults to incremental completion described above.  If a
completion list is preferred, then change this to 'complete.  If you
just want a completion list once, then use the universal argument ARG
to change it temporarily."
  (interactive "P")
  (matlab-navigation-syntax
    (let* ((prefix (if (and (not (eq last-command 'matlab-complete-symbol))
			    (member (preceding-char) '(?  ?\t ?\n ?, ?\( ?\[ ?\')))
		       ""
		     (buffer-substring-no-properties
		      (save-excursion (forward-word -1) (point))
		      (point))))
	   (sem (matlab-lattr-semantics prefix))
	   (matlab-completion-technique
	    (if arg (cond ((eq matlab-completion-technique 'complete)
			   'increment)
			  (t 'complete))
	      matlab-completion-technique)))
      (if (not (eq last-command 'matlab-complete-symbol))
	  (setq matlab-last-prefix prefix
		matlab-last-semantic sem
		matlab-completion-search-state
		(cond ((eq sem 'solo)
		       '(matlab-solo-completions
			 matlab-find-user-functions
			 matlab-find-recent-variable))
		      ((eq sem 'boolean)
		       '(matlab-find-recent-variable
			 matlab-boolean-completions
			 matlab-find-user-functions
			 matlab-value-completions))
		      ((eq sem 'value)
		       '(matlab-find-recent-variable
			 matlab-find-user-functions
			 matlab-value-completions
			 matlab-boolean-completions))
		      ((eq sem 'property)
		       '(matlab-property-completions
			 matlab-find-user-functions
			 matlab-find-recent-variable
			 matlab-value-completions))
		      (t '(matlab-find-recent-variable
			   matlab-find-user-functions
			   matlab-value-completions
			   matlab-boolean-completions)))))
      (cond
       ((eq matlab-completion-technique 'increment)
	(let ((r nil) (donext (eq last-command 'matlab-complete-symbol)))
	  (while (and (not r) matlab-completion-search-state)
	    (message "Expand with %S" (car matlab-completion-search-state))
	    (setq r (funcall (car matlab-completion-search-state)
			     matlab-last-prefix donext))
	    (if (not r) (setq matlab-completion-search-state
			      (cdr matlab-completion-search-state)
			      donext nil)))
	  (delete-region (point) (progn (forward-char (- (length prefix)))
					(point)))
	  (if r
	      (insert r)
	    (insert matlab-last-prefix)
	    (message "No completions."))))
       ((eq matlab-completion-technique 'complete)
	(let ((allsyms (apply 'append
			      (mapcar (lambda (f) (funcall f prefix))
				      matlab-completion-search-state))))
	  (cond ((null allsyms)
		 (message "No completions.")
		 (ding))
		((= (length allsyms) 1)
		 (delete-region (point) (progn
					  (forward-char (- (length prefix)))
					  (point)))
		 (insert (car allsyms)))
		((= (length allsyms) 0)
		 (message "No completions."))
		(t
		 (let* ((al (mapcar (lambda (a) (list a)) allsyms))
			(c (try-completion prefix al)))
		   ;; This completion stuff lets us expand as much as is
		   ;; available to us. When the completion is the prefix
		   ;; then we want to display all the strings we've
		   ;; encountered.
		   (if (and (stringp c) (not (string= prefix c)))
		       (progn
			 (delete-region
			  (point)
			  (progn (forward-char (- (length prefix)))
				 (point)))
			 (insert c))
		     ;; `display-completion-list' does all the complex
		     ;; ui work for us.
		     (with-output-to-temp-buffer "*Completions*"
		       (display-completion-list
			(matlab-uniquafy-list allsyms)))))))))))))

(defun matlab-insert-end-block ()
  "Insert and END block based on the current syntax."
  (interactive)
  (if (not (matlab-ltype-empty)) (progn (end-of-line) (insert "\n")))
  (let ((valid t))
    (save-excursion
      (condition-case nil
	  (progn
	    (matlab-backward-sexp t)
	    (setq valid (buffer-substring-no-properties
			 (point) (save-excursion
				   (re-search-forward "[\n,;.]" nil t)
				   (point)))))
	(error (setq valid nil))))
    (if (not valid)
	(error "No block to end")
      (insert "end")
      (if (stringp valid) (insert " % " valid))
      (matlab-indent-line))))

(tempo-define-template
 "matlab-for"
 '("for " p "=" p "," > n>
     r> &
     "end" > %)
 "for"
 "Insert a Matlab for statement"
 'matlab-tempo-tags
 )

(tempo-define-template
 "matlab-while"
 '("while (" p ")," > n>
     r> &
     "end" > %)
 "while"
 "Insert a Matlab while statement"
 'matlab-tempo-tags
 )

(tempo-define-template
 "matlab-if"
 '("if " p > n
     r>
     "end" > n)
 "if"
 "Insert a Matlab if statement"
 'matlab-tempo-tags
 )

(tempo-define-template
 "matlab-if-else"
 '("if " p > n
     r>
     "else" > n
     "end" > n)
 "if"
 "Insert a Matlab if statement"
 'matlab-tempo-tags
 )

(tempo-define-template
 "matlab-try"
 '("try " > n
     r>
     "catch" > n
     p > n
     "end" > n)
 "try"
 "Insert a Matlab try catch statement"
 'matlab-tempo-tags
 )

(tempo-define-template
 "matlab-switch"
 '("switch " p > n
     "otherwise" > n
     r>
     "end" > n)
 "switch"
 "Insert a Matlab switch statement with region in the otherwise clause."
 'matlab-tempo-tags)

(defun matlab-insert-next-case ()
  "Insert a case statement inside this switch statement."
  (interactive)
  ;; First, make sure we are where we think we are.
  (let ((valid t))
    (save-excursion
      (condition-case nil
	  (progn
	   (matlab-backward-sexp t)
	   (setq valid (looking-at "switch")))
	(error (setq valid nil))))
    (if (not valid)
	(error "Not in a switch statement")))
  (if (not (matlab-ltype-empty)) (progn (end-of-line) (insert "\n")))
  (indent-to 0)
  (insert "case ")
  (matlab-indent-line))

(tempo-define-template
 "matlab-function"
 '("function "
     (P "output argument(s): " output t)
     ;; Insert brackets only if there is more than one output argument
     (if (string-match "," (tempo-lookup-named 'output))
	 '(l "[" (s output) "]")
       '(l (s output)))
     ;; Insert equal sign only if there is output argument(s)
     (if (= 0 (length (tempo-lookup-named 'output))) nil
       " = ")
     ;; The name of a function, as defined in the first line, should
     ;; be the same as the name of the file without .m extension
     (if (= 1 (count-lines 1 (point)))
	 (tempo-save-named
	  'fname
	  (file-name-nondirectory (file-name-sans-extension
				   (buffer-file-name))))
       '(l (P "function name: " fname t)))
     (tempo-lookup-named 'fname)
     "("  (P "input argument(s): ") ")" n
     "% " (upcase (tempo-lookup-named 'fname)) " - " (P "H1 line: ") n
     "%   " p n)
 "function"
 "Insert a Matlab function statement"
 'matlab-tempo-tags
 )

(defun matlab-stringify-region (begin end)
  "Put Matlab 's around region, and quote all quotes in the string.
Stringification allows you to type in normal Matlab code, mark it, and
then turn it into a Matlab string that will output exactly what's in
the region.  BEGIN and END mark the region to be stringified."
  (interactive "r")
  (save-excursion
    (goto-char begin)
    (if (re-search-forward "\n" end t)
	(error
	 "You may only stringify regions that encompass less than one line"))
    (let ((m (make-marker)))
      (move-marker m end)
      (goto-char begin)
      (insert "'")
      (while (re-search-forward "'" m t)
	(insert "'"))
      (goto-char m)
      (insert "'"))))

;;; Block highlighting ========================================================

(defvar matlab-block-highlighter-timer nil
  "The timer representing the block highlighter.")

(defun matlab-enable-block-highlighting (&optional arg)
  "Start or stop the block highlighter.
Optional ARG is 1 to force enable, and -1 to disable.
If ARG is nil, then highlighting is toggled."
  (interactive "P")
  (if (not (fboundp 'matlab-run-with-idle-timer))
      (setq matlab-highlight-block-match-flag nil))
  ;; Only do it if it's enabled.
  (if (not matlab-highlight-block-match-flag)
      nil
    ;; Use post command idle hook as a local hook to dissuade too much
    ;; cpu time while doing other things.
    ;;(make-local-hook 'post-command-hook)
    (if (not arg)
	(setq arg
	      (if (member 'matlab-start-block-highlight-timer
			  post-command-hook)
		  -1 1)))
    (if (> arg 0)
	(add-hook 'post-command-hook 'matlab-start-block-highlight-timer)
      (remove-hook 'post-command-hook 'matlab-start-block-highlight-timer))))

(defvar matlab-block-highlight-overlay nil
  "The last highlighted overlay.")
(make-variable-buffer-local 'matlab-block-highlight-overlay)

(defvar matlab-block-highlight-timer nil
  "Last started timer.")
(make-variable-buffer-local 'matlab-block-highlight-timer)

(defun matlab-start-block-highlight-timer ()
  "Set up a one-shot timer if we are in Matlab mode."
  (if (eq major-mode 'matlab-mode)
      (progn
	(if matlab-block-highlight-overlay
	    (unwind-protect
		(matlab-delete-overlay matlab-block-highlight-overlay)
	      (setq matlab-block-highlight-overlay nil)))
	(if matlab-block-highlight-timer
	    (unwind-protect
		(matlab-cancel-timer matlab-block-highlight-timer)
	      (setq matlab-block-highlight-timer nil)))
	(setq matlab-block-highlight-timer
	      (matlab-run-with-idle-timer
	       1 nil 'matlab-highlight-block-match)))))
  
(defun matlab-highlight-block-match ()
  "Highlight a matching block if available."
  (setq matlab-block-highlight-timer nil)
  (let ((inhibit-quit nil)		;turn on G-g
	(matlab-scan-on-screen-only t))
    (if matlab-show-periodic-code-details-flag
	(matlab-show-line-info))
    (if (not (matlab-cursor-in-string-or-comment))
	(save-excursion
	  (if (or (bolp)
		  (looking-at "\\s-")
		  (save-excursion (forward-char -1) (looking-at "\\s-")))
	      nil
	    (forward-word -1))
	  (if (and (looking-at (concat (matlab-block-beg-re) "\\>"))
		   (not (looking-at "function")))
	      (progn
		;; We scan forward...
		(matlab-forward-sexp)
		(backward-word 1)
		(if (not (looking-at "end"))
		    nil ;(message "Unterminated block, or end off screen.")
		  (setq matlab-block-highlight-overlay
			(matlab-make-overlay (point)
					     (progn (forward-word 1)
						    (point))
					     (current-buffer)))
		  (matlab-overlay-put matlab-block-highlight-overlay
				      'face 'matlab-region-face)))
	    (if (and (looking-at (concat (matlab-block-end-pre) "\\>"))
		     (not (looking-at "function"))
		     (matlab-valid-end-construct-p))
		(progn
		  ;; We scan backward
		  (forward-word 1)
		  (condition-case nil
		      (progn
			(matlab-backward-sexp)
			(if (not (looking-at (matlab-block-beg-re)))
			    nil ;(message "Unstarted block at cursor.")
			  (setq matlab-block-highlight-overlay
				(matlab-make-overlay (point)
						     (progn (forward-word 1)
							    (point))
						     (current-buffer)))
			  (matlab-overlay-put matlab-block-highlight-overlay
					      'face 'matlab-region-face)))
		    (error (message "Unstarted block at cursor."))))
	      ;; do nothing
	      ))))))

;;; M Code verification & Auto-fix ============================================

(defvar matlab-mode-verify-fix-functions
  '(matlab-mode-vf-functionname
    matlab-mode-vf-block-matches-forward
    matlab-mode-vf-block-matches-backward)
  "List of function symbols which perform a verification and fix to M code.
Each function gets no arguments, and returns nothing.  They can move
point, but it will be restored for them.")

(defun matlab-mode-verify-fix-file-fn ()
  "Verify the current buffer from `write-contents-hooks'."
  (if matlab-verify-on-save-flag
      (matlab-mode-verify-fix-file (> (point-max)
				      matlab-block-verify-max-buffer-size)))
  ;; Always return nil.
  nil)

(defun matlab-mode-verify-fix-file (&optional fast)
  "Verify the current buffer satisfies all M things that might be useful.
We will merely loop across a list of verifiers/fixers in
`matlab-mode-verify-fix-functions'.
If optional FAST is non-nil, do not perform usually lengthy checks."
  (interactive)
  (let ((p (point))
	(l matlab-mode-verify-fix-functions))
    (while l
      (funcall (car l) fast)
      (setq l (cdr l)))
    (goto-char p))
  (if (interactive-p)
      (message "Done.")))

;;
;; Add more auto verify/fix functions here!
;;
(defun matlab-mode-vf-functionname (&optional fast)
  "Verify/Fix the function name of this file.
Optional argument FAST is ignored."
  (matlab-navigation-syntax
    (goto-char (point-min))
    (while (and (or (matlab-ltype-empty) (matlab-ltype-comm))
		(/= (matlab-point-at-eol) (point-max)))
      (forward-line 1))
    (let ((func nil)
	  (bn (file-name-sans-extension
	       (file-name-nondirectory (buffer-file-name)))))
    (if (looking-at
	 ;; old function was too unstable.
	 ;;"\\(^function\\s-+\\)\\([^=\n]+=[ \t\n.]*\\)?\\(\\sw+\\)"
	 (concat "\\(^\\s-*function\\b[ \t\n.]*\\)\\(\\(\\[[^]]*\\]\\|\\sw+\\)"
		 "[ \t\n.]*=[ \t\n.]*\\)?\\(\\sw+\\)"))
	;; The expression above creates too many numeric matches
	;; to apply a known one to our function.  We cheat by knowing that
	;; match-end 0 is at the end of the function name.  We can then go
	;; backwards, and get the extents we need.  Navigation syntax
	;; lets us know that backward-word really covers the word.
	(let ((end (match-end 0))
	      (begin (progn (goto-char (match-end 0))
			    (forward-word -1)
			    (point))))
	  (setq func (buffer-substring begin end))
	  (if (not (string= func bn))
	      (if (not (matlab-mode-highlight-ask
			begin end
			"Function and file names are different. Fix?"))
		  nil
		(goto-char begin)
		(delete-region begin end)
		(insert bn))))))))

(defun matlab-mode-vf-block-matches-forward (&optional fast)
  "Verify/Fix unterminated (or un-ended) blocks.
This only checks block regions like if/end.
Optional argument FAST causes this check to be skipped."
  (goto-char (point-min))
  (let ((go t)
	(expr (concat "\\<\\(" (matlab-block-beg-pre) "\\)\\>")))
    (matlab-navigation-syntax
      (while (and (not fast) go (re-search-forward expr nil t))
	(forward-word -1)		;back over the special word
	(let ((s (point)))
	  (condition-case nil
	      (if (and (not (matlab-cursor-in-string-or-comment))
		       (not (looking-at "function")))
		  (progn
		    (matlab-forward-sexp)
		    (forward-word -1)
		    (if (not (looking-at "end\\>")) (setq go nil)))
		(forward-word 1))
	    (error (setq go nil)))
	  (if (and (not go) (goto-char s)
		   (not (matlab-mode-highlight-ask
			 (point) (save-excursion (forward-word 1) (point))
			 "Unterminated block.  Continue anyway?")))
	      (error "Unterminated Block found!")))
	(message "Block-check: %d%%" (/ (/ (* 100 (point)) (point-max)) 2))))))
  
(defun matlab-mode-vf-block-matches-backward (&optional fast)
  "Verify/fix unstarted (or dangling end) blocks.
Optional argument FAST causes this check to be skipped."
  (goto-char (point-max))
  (let ((go t) (expr (concat "\\<\\(" (matlab-block-end-no-function-re)
			     "\\)\\>")))
    (matlab-navigation-syntax
      (while (and (not fast) go (re-search-backward expr nil t))
	(forward-word 1)
	(let ((s (point)))
	  (condition-case nil
	      (if (and (not (matlab-cursor-in-string-or-comment))
		       (matlab-valid-end-construct-p))
		  (matlab-backward-sexp)
		(backward-word 1))
	    (error (setq go nil)))
	  (if (and (not go) (goto-char s)
		   (not (matlab-mode-highlight-ask
			 (point) (save-excursion (backward-word 1) (point))
			 "Unstarted block.  Continue anyway?")))
	      (error "Unstarted Block found!")))
	(message "Block-check: %d%%"
		 (+ (/ (/ (* 100 (- (point-max) (point))) (point-max)) 2) 50))))))

;;; Utility for verify/fix actions if you need to highlight
;;  a section of the buffer for the user's approval.
(defun matlab-mode-highlight-ask (begin end prompt)
  "Highlight from BEGIN to END while asking PROMPT as a yes-no question."
  (let ((mo (matlab-make-overlay begin end (current-buffer)))
	(ans nil))
    (condition-case nil
	(progn
	  (matlab-overlay-put mo 'face 'matlab-region-face)
	  (setq ans (y-or-n-p prompt))
	  (matlab-delete-overlay mo))
      (quit (matlab-delete-overlay mo) (error "Quit")))
    ans))

;;; V19 stuff =================================================================

(defun matlab-mode-hilit ()
  "Set up hilit19 support for `matlab-mode'."
  (interactive)
  (cond (window-system
	 (setq hilit-mode-enable-list  '(not text-mode)
	       hilit-background-mode   'light
	       hilit-inhibit-hooks     nil
	       hilit-inhibit-rebinding nil)
	 (require 'hilit19)
	 (hilit-set-mode-patterns 'matlab-mode matlab-hilit19-patterns))))

(defvar matlab-mode-menu-keymap nil
  "Keymap used in Matlab mode to provide a menu.")

(defun matlab-frame-init ()
  (interactive)
  ;;(modify-frame-parameters (selected-frame) '((menu-bar-lines . 2)))
  ;; make a menu keymap
  (easy-menu-define
   matlab-mode-menu
   matlab-mode-map
   "Matlab menu"
   '("Matlab"
     ["Start Matlab" matlab-shell t]
     ["Save and go" matlab-shell-save-and-go t]
     ["Run Region" matlab-shell-run-region t]
     ["Verify/Fix source" matlab-mode-verify-fix-file t]
     ["Version" matlab-show-version t]
     "----"
     ["Find M file" matlab-find-file-on-path t]
     ("Navigate"
      ["Beginning of Command" matlab-beginning-of-command t]
      ["End of Command" matlab-end-of-command t]
      ["Forward Block" matlab-forward-sexp t]
      ["Backward Block" matlab-backward-sexp t]
      ["Beginning of Function" matlab-beginning-of-defun t]
      ["End of Function" matlab-end-of-defun t])
     ("Format"
      ["Justify Line" matlab-justify-line t]
      ["Fill Region" matlab-fill-region t]
      ["Fill Comment Paragraph" matlab-fill-paragraph
       (save-excursion (matlab-comment-on-line))]
      ["Join Comment" matlab-join-comment-lines
       (save-excursion (matlab-comment-on-line))]
      ["Comment Region" matlab-comment-region t])
     ("Insert"
      ["Complete Symbol" matlab-complete-symbol t]
      ["Comment" matlab-comment t]
      ["if end" tempo-template-matlab-if t]
      ["if else end" tempo-template-matlab-if-else t]
      ["for end" tempo-template-matlab-for t]
      ["switch otherwise end" tempo-template-matlab-switch t]
      ["Next case" matlab-insert-next-case t]
      ["try catch end" tempo-template-matlab-try t]
      ["while end" tempo-template-matlab-while t]
      ["End of block" matlab-insert-end-block t]
      ["Function" tempo-template-matlab-function t]
      ["Stringify Region" matlab-stringify-region t]
      )
     ("Customize"
;      ["Auto Fill Counts Elipsis"
;       (lambda () (setq matlab-fill-count-ellipsis-flag
;			(not matlab-fill-count-ellipsis-flag)))
;       :style toggle :selected 'matlab-fill-count-ellipsis-flag]
      ["Indent Function Body"
       (setq matlab-indent-function (not matlab-indent-function))
       :style toggle :selected 'matlab-indent-function]
      ["Verify File on Save"
       (setq matlab-verify-on-save-flag (not matlab-verify-on-save-flag))
       :style toggle :selected 'matlab-verify-on-save-flag]
      ["Highlight Matching Blocks"
       (matlab-enable-block-highlighting)
       :style toggle :selected (member 'matlab-start-block-highlight-timer
				       post-command-hook) ]
      
      ["Customize" (lambda () (interactive) (customize-group 'matlab))
       (and (featurep 'custom) (fboundp 'custom-declare-variable)) ]
      )
     "----"
     ["Run M Command" matlab-shell-run-command (matlab-shell-active-p)]
     ["Describe Command" matlab-shell-describe-command (matlab-shell-active-p)]
     ["Describe Variable" matlab-shell-describe-variable (matlab-shell-active-p)]
     ["Command Apropos" matlab-shell-apropos (matlab-shell-active-p)]
     ["Topic Browser" matlab-shell-topic-browser (matlab-shell-active-p)]
     ))
  (easy-menu-add matlab-mode-menu matlab-mode-map))

;;; Matlab shell =============================================================

(defgroup matlab-shell nil
  "Matlab shell mode."
  :prefix "matlab-shell-"
  :group 'matlab)

(defcustom matlab-shell-command "matlab"
  "*The name of the command to be run which will start the Matlab process."
  :group 'matlab-shell
  :type 'string)

(defcustom matlab-shell-command-switches ""
  "*Command line parameters run with `matlab-shell-command'."
  :group 'matlab-shell
  :type '(repeat (string :tag "Switch: ")))

(defcustom matlab-shell-enable-gud-flag t
  "*Non-nil means to use GUD mode when running the Matlab shell."
  :group 'matlab-shell
  :type 'boolean)

(defcustom matlab-shell-mode-hook nil
  "*List of functions to call on entry to Matlab shell mode."
  :group 'matlab-shell
  :type 'hook)

(defvar matlab-shell-buffer-name "Matlab"
  "Name used to create `matlab-shell' mode buffers.
This name will have *'s surrounding it.")

(defun matlab-shell-active-p ()
  "Return t if the Matlab shell is active."
  (if (get-buffer (concat "*" matlab-shell-buffer-name "*"))
      (save-excursion
	(set-buffer (concat "*" matlab-shell-buffer-name "*"))
	(if (comint-check-proc (current-buffer))
	    (current-buffer)))))

(defvar matlab-shell-mode-map ()
  "Keymap used in `matlab-shell-mode'.")

(defvar matlab-shell-font-lock-keywords-1
  (append matlab-font-lock-keywords matlab-shell-font-lock-keywords)
  "Keyword symbol used for font-lock mode.")

(defvar matlab-shell-font-lock-keywords-2
  (append matlab-shell-font-lock-keywords-1 matlab-gaudy-font-lock-keywords)
  "Keyword symbol used for gaudy font-lock symbols.")

(defvar matlab-shell-font-lock-keywords-3
  (append matlab-shell-font-lock-keywords-2
	  matlab-really-gaudy-font-lock-keywords)
  "Keyword symbol used for really gaudy font-lock symbols.")

(eval-when-compile (require 'gud))

;;;###autoload
(defun matlab-shell ()
  "Create a buffer with Matlab running as a subprocess."
  (interactive)
  (require 'shell)
  (require 'gud)

  ;; Make sure this is safe...
  (if (and matlab-shell-enable-gud-flag (fboundp 'gud-make-debug-menu))
      ;; We can continue using GUD
      nil
    (message "Sorry, your emacs cannot use the Matlab Shell GUD features.")
    (setq matlab-shell-enable-gud-flag nil))

  (switch-to-buffer (concat "*" matlab-shell-buffer-name "*"))
  (if (matlab-shell-active-p)
      nil
    ;; Build keymap here in case someone never uses comint mode
    (if matlab-shell-mode-map
	()
      (setq matlab-shell-mode-map
	    (let ((km (make-sparse-keymap 'matlab-shell-mode-map)))
	      (set-keymap-parent km comint-mode-map)
	      (substitute-key-definition 'next-error 'matlab-shell-last-error
					 km global-map)
	      (define-key km [(control h) (control m)]
		matlab-help-map)
	      (define-key km [(tab)]
		'comint-dynamic-complete-filename)
	      (define-key km [(control up)]
		'comint-previous-matching-input-from-input)
	      (define-key km [(control down)]
		'comint-next-matching-input-from-input)
	      (define-key km [up]
		'comint-previous-matching-input-from-input)
	      (define-key km [down]
		'comint-next-matching-input-from-input)
	      (define-key km [(control return)] 'comint-kill-input)
	      km)))
    (switch-to-buffer
     (make-comint matlab-shell-buffer-name matlab-shell-command
		  nil matlab-shell-command-switches))
    
    (setq shell-dirtrackp t)
    (comint-mode)

    (if matlab-shell-enable-gud-flag
	(progn
	  (gud-mode)
	  (make-local-variable 'gud-marker-filter)
	  (setq gud-marker-filter 'gud-matlab-marker-filter)
	  (make-local-variable 'gud-find-file)
	  (setq gud-find-file 'gud-matlab-find-file)

	  (set-process-filter (get-buffer-process (current-buffer))
			      'gud-filter)
	  (set-process-sentinel (get-buffer-process (current-buffer))
				'gud-sentinel)
	  (gud-set-buffer))
      ;; What to do when there is no GUD
      ;(set-process-filter (get-buffer-process (current-buffer))
	;		  'matlab-shell-process-filter)
      )

    ;; Comint and GUD both try to set the mode.  Now reset it to
    ;; matlab mode.
    (matlab-shell-mode)))

(defcustom matlab-shell-logo
  (if (fboundp 'locate-data-file)
      ;; Starting from XEmacs 20.4 use locate-data-file
      (locate-data-file "matlab.xpm")
    (expand-file-name "matlab.xpm" data-directory))
  "*The Matlab logo file."
  :group 'matlab-shell
  :type '(choice (const :tag "None" nil)
		 (file :tag "File" "")))

 
(defun matlab-shell-hack-logo (str)
  "Replace the text logo with a real logo.
STR is passed from the commint filter."
  (when (string-match "< M A T L A B (R) >" str)
    (save-excursion
      (when (re-search-backward "^[ \t]+< M A T L A B (R) >" (point-min) t)
 	(delete-region (match-beginning 0) (match-end 0))
 	(insert (make-string 16 ? ))
 	(set-extent-begin-glyph (make-extent (point) (point))
 				(make-glyph matlab-shell-logo))))
    ;; Remove this function from `comint-output-filter-functions'
    (remove-hook 'comint-output-filter-functions
 		 'matlab-shell-hack-logo)))

(defun matlab-shell-mode ()
  "Run Matlab as a subprocess in an Emacs buffer.

This mode will allow standard Emacs shell commands/completion to occur
with Matlab running as an inferior process.  Additionally, this shell
mode is integrated with `matlab-mode', a major mode for editing M
code.

> From an M file buffer:
\\<matlab-mode-map>
\\[matlab-shell-save-and-go] - Save the current M file, and run it in a \
Matlab shell.

> From Shell mode:
\\<matlab-shell-mode-map>
\\[matlab-shell-last-error] - find location of last Matlab runtime error \
in the offending M file.

> From an M file, or from Shell mode:
\\<matlab-mode-map>
\\[matlab-shell-run-command] - Run COMMAND and show result in a popup buffer.
\\[matlab-shell-describe-variable] - Show variable contents in a popup buffer.
\\[matlab-shell-describe-command] - Show online documentation for a command\
in a popup buffer.
\\[matlab-shell-apropos] - Show output from LOOKFOR command in a popup buffer.
\\[matlab-shell-topic-browser] - Topic browser using HELP.

> Keymap:
\\{matlab-mode-map}"
  (setq major-mode 'matlab-shell-mode
	mode-name "M-Shell"
	comint-prompt-regexp "^K?>> *"
	comint-delimiter-argument-list (list [ 59 ]) ; semi colon
	comint-dynamic-complete-functions '(comint-replace-by-expanded-history)
	comint-process-echoes t
	)
  ;;(add-hook 'comint-input-filter-functions 'shell-directory-tracker)
  ;; Add a spiffy logo if we are running XEmacs
  (if (and (string-match "XEmacs" emacs-version)
	   (stringp matlab-shell-logo)
	   (file-readable-p matlab-shell-logo))
      (add-hook 'comint-output-filter-functions 'matlab-shell-hack-logo))
  (make-local-variable 'comment-start)
  (setq comment-start "%")
  (use-local-map matlab-shell-mode-map)
  (set-syntax-table matlab-mode-syntax-table)
  (make-local-variable 'font-lock-defaults)
  (setq font-lock-defaults '((matlab-shell-font-lock-keywords-1
			      matlab-shell-font-lock-keywords-2
			      matlab-shell-font-lock-keywords-3)
			     t nil ((?_ . "w"))))
  
  (easy-menu-define
   matlab-shell-menu
   matlab-shell-mode-map
   "Matlab shell menu"
   '("Matlab"
     ["Goto last error" matlab-shell-last-error t]
     "----"
     ["Stop On Errors" matlab-shell-dbstop-error t]
     ["Don't Stop On Errors" matlab-shell-dbclear-error t]
     "----"
     ["Run Command" matlab-shell-run-command t]
     ["Describe Variable" matlab-shell-describe-variable t]
     ["Describe Command" matlab-shell-describe-command t]
     ["Lookfor Command" matlab-shell-apropos t]
     ["Topic Browser" matlab-shell-topic-browser t]
     "----"
     ["Demos" matlab-shell-demos t]
     ["Close Current Figure" matlab-shell-close-current-figure t]
     ["Close Figures" matlab-shell-close-figures t]
     "----"
     ["Exit" matlab-shell-exit t]))
  (easy-menu-add matlab-shell-menu matlab-shell-mode-map)
  
  (if matlab-shell-enable-gud-flag
      (progn
	(gud-def gud-break  "dbstop at %l in %f"  "\C-b" "Set breakpoint at current line.")
	(gud-def gud-remove "dbclear at %l in %f" "\C-d" "Remove breakpoint at current line")
	(gud-def gud-step   "dbstep %p"           "\C-s" "Step one source line with display.")
	(gud-def gud-cont   "dbcont"              "\C-r" "Continue with display.")
	(gud-def gud-finish "dbquit"              "\C-f" "Finish executing current function.")
	(gud-def gud-up     "dbup %p"             "<"    "Up N stack frames (numeric arg).")
	(gud-def gud-down   "dbdown %p"           ">"    "Down N stack frames (numeric arg).")
	(gud-def gud-print  "%e"                  "\C-p" "Evaluate M expression at point.")

	(gud-make-debug-menu)))
  
  (run-hooks 'matlab-shell-mode-hook)
  (matlab-show-version)
  )

(defvar gud-matlab-marker-regexp-1 "^K>>"
  "Regular expression for finding a file line-number.")

(defvar gud-matlab-marker-regexp-2
  "^> In \\([-.a-zA-Z0-9_/]+\\) at line \\([0-9]+\\)[ \n]+"
  "Regular expression for finding a file line-number.
Please note: The > character represents the current stack frame, so if there
are several frames, this makes sure we pick the right one to popup.")

(defvar gud-matlab-error-regexp (concat "\\(Error\\|Syntax error\\) in ==> "
					"\\([-.a-zA-Z_0-9/]+\\).*\nOn line "
					"\\([0-9]+\\) ")
  "Regular expression finding where an error occurred.")

(defvar matlab-last-frame-returned nil
  "Store the previously returned frame for Matlabs difficult debugging output.
It is reset to nil whenever we are not prompted by the K>> output.")

(defvar matlab-one-db-request nil
  "Set to t if we requested a debugger command trace.")

(defun gud-matlab-marker-filter (string)
  "Filters STRING for the Unified Debugger based on Matlab output.
Swiped ruthlessly from GDB mode in gud.el"
  (let ((garbage (concat "\\(" (regexp-quote "\C-g") "\\|"
 			 (regexp-quote "\033[H0") "\\|"
 			 (regexp-quote "\033[H\033[2J") "\\|"
 			 (regexp-quote "\033H\033[2J") "\\)")))
    (while (string-match garbage string)
      (if (= (aref (buffer-string) (match-beginning 0)) ?\C-g)
	  (beep t))
      (setq string (replace-match "" t t string))))
  (setq gud-marker-acc (concat gud-marker-acc string))
  (let ((output "") (frame nil))

    ;; Remove output from one stack trace...
    (if (eq matlab-one-db-request t)
	(if (string-match "db[a-z]+[ \n]+" gud-marker-acc)
	    (setq gud-marker-acc (substring gud-marker-acc (match-end 0))
		  matlab-one-db-request 'prompt)))

    ;; Process all the complete markers in this chunk.
    (while (and (not (eq matlab-one-db-request t))
		(string-match gud-matlab-marker-regexp-2 gud-marker-acc))

      (setq

       ;; Extract the frame position from the marker.
       frame (cons (match-string 1 gud-marker-acc)
		   (string-to-int (substring gud-marker-acc
					     (match-beginning 2)
					     (match-end 2))))

       ;; Append any text before the marker to the output we're going
       ;; to return - we don't include the marker in this text.
       ;; If this is not a requested piece of text, then include
       ;; it into the output.
       output (concat output
		      (substring gud-marker-acc 0
				 (if matlab-one-db-request
				     (match-beginning 0)
				   (match-end 0))))

       ;; Set the accumulator to the remaining text.
       gud-marker-acc (substring gud-marker-acc (match-end 0))))

    (if frame
	(progn
	  ;; We have a frame, so we don't need to do extra checking.
	  (setq matlab-last-frame-returned frame)
	  )
      (if (and (not matlab-one-db-request)
	       (string-match gud-matlab-marker-regexp-1 gud-marker-acc))
	  (progn
	    ;; Here we know we are in debug mode, so find our stack, and
	    ;; deal with that later...
	    (setq matlab-one-db-request t)
	    (process-send-string (get-buffer-process gud-comint-buffer)
				 "dbstack\n"))))

    ;; Check for a prompt to nuke...
    (if (and (eq matlab-one-db-request 'prompt)
	     (string-match "^K?>> $" gud-marker-acc))
	(setq matlab-one-db-request nil
	      output ""
	      gud-marker-acc (substring gud-marker-acc (match-end 0))))

    ;; Finish off this part of the output.  None of our special stuff
    ;; ends with a \n, so display those as they show up...
    (while (string-match "^[^\n]*\n" gud-marker-acc)
      (setq output (concat output (substring gud-marker-acc 0 (match-end 0)))
	    gud-marker-acc (substring gud-marker-acc (match-end 0))))

    (if (and (string-match ">> $" gud-marker-acc)
	     (>= (match-end 0) (length gud-marker-acc)))
	(setq output (concat output gud-marker-acc)
	      gud-marker-acc ""))

    (if frame (setq gud-last-frame frame))

    ;;(message "[%s] [%s]" output gud-marker-acc)

    output))

(defun gud-matlab-find-file (f)
  "Find file F when debugging frames in Matlab."
  (save-excursion
    (let ((buf (find-file-noselect f)))
      (set-buffer buf)
      (gud-make-debug-menu)
      buf)))

;;; Matlab Shell Commands =====================================================

(defun matlab-read-word-at-point ()
  "Get the word closest to point, but do not change position.
Has a preference for looking backward when not directly on a symbol.
Snatched and hacked from dired-x.el"
  (let ((word-chars "a-zA-Z0-9_")
	(bol (matlab-point-at-bol))
	(eol (matlab-point-at-eol))
        start)
    (save-excursion
      ;; First see if just past a word.
      (if (looking-at (concat "[" word-chars "]"))
	  nil
	(skip-chars-backward (concat "^" word-chars "{}()\[\]") bol)
	(if (not (bobp)) (backward-char 1)))
      (if (numberp (string-match (concat "[" word-chars "]")
				 (char-to-string (following-char))))
          (progn
            (skip-chars-backward word-chars bol)
            (setq start (point))
            (skip-chars-forward word-chars eol))
        (setq start (point)))		; If no found, return empty string
      (buffer-substring start (point)))))

(defun matlab-read-line-at-point ()
  "Get the line under point, if command line."
  (if (eq major-mode 'matlab-shell-mode)
      (save-excursion
	(beginning-of-line)
	(if (not (looking-at (concat comint-prompt-regexp)))
	    ""
	  (search-forward-regexp comint-prompt-regexp)
	  (buffer-substring (point) (matlab-point-at-eol))))
    (save-excursion
      ;; In matlab buffer, find all the text for a command.
      ;; so back over until there is no more continuation.
      (while (save-excursion (forward-line -1) (matlab-lattr-cont))
	(forward-line -1))
      ;; Go forward till there is no continuation
      (beginning-of-line)
      (let ((start (point)))
	(while (matlab-lattr-cont) (forward-line 1))
	(end-of-line)
	(buffer-substring start (point))))))

(defun matlab-non-empty-lines-in-string (str)
  "Return number of non-empty lines in STR."
  (let ((count 0)
	(start 0))
    (while (string-match "^.+$" str start)
      (setq count (1+ count)
	    start (match-end 0)))
    count))

(defun matlab-output-to-temp-buffer (buffer output)
  ;; Print output to temp buffer, or a message if empty string
  (let ((lines-found (matlab-non-empty-lines-in-string output)))
    (cond ((= lines-found 0)
	   (message "(Matlab command completed with no output)"))
	  ((= lines-found 1)
	   (string-match "^.+$" output)
	   (message (substring output (match-beginning 0)(match-end 0))))
	  (t (with-output-to-temp-buffer buffer (princ output))
	     (save-excursion
	       (set-buffer buffer)
	       (matlab-shell-help-mode))))))

(defun matlab-shell-run-command (command)
  "Run COMMAND and display result in a buffer.
This command requires an active Matlab shell."
  (interactive (list (read-from-minibuffer
 		      "Matlab command line: "
 		      (cons (matlab-read-line-at-point) 0))))
  (let ((doc (matlab-shell-collect-command-output command)))
    (matlab-output-to-temp-buffer "*Matlab Help*" doc)))

(defun matlab-shell-describe-variable (variable)
  "Get the contents of VARIABLE and display them in a buffer.
This uses the WHOS (Matlab 5) command to find viable commands.
This command requires an active Matlab shell."
  (interactive (list (read-from-minibuffer
 		      "Matlab variable: "
 		      (cons (matlab-read-word-at-point) 0))))
  (let ((doc (matlab-shell-collect-command-output (concat "whos " variable))))
    (matlab-output-to-temp-buffer "*Matlab Help*" doc)))

(defun matlab-shell-describe-command (command)
  "Describe COMMAND textually by fetching it's doc from the Matlab shell.
This uses the lookfor command to find viable commands.
This command requires an active Matlab shell."
  (interactive
   (let ((fn (matlab-function-called-at-point))
	 val)
     (setq val (read-string (if fn
				(format "Describe function (default %s): " fn)
			      "Describe function: ")))
     (if (string= val "") (list fn) (list val))))
  (let ((doc (matlab-shell-collect-command-output (concat "help " command))))
    (matlab-output-to-temp-buffer "*Matlab Help*" doc)))

(defun matlab-shell-apropos (matlabregex)
  "Look for any active commands in MATLAB matching MATLABREGEX.
This uses the lookfor command to find viable commands."
  (interactive (list (read-from-minibuffer
 		      "Matlab command subexpression: "
 		      (cons (matlab-read-word-at-point) 0))))
  (let ((ap (matlab-shell-collect-command-output
	     (concat "lookfor " matlabregex))))
    (matlab-output-to-temp-buffer "*Matlab Apropos*" ap)))
  
(defun matlab-shell-run-region (beg end)
  "Run region from BEG to END and display result in Matlab shell.
This command requires an active Matlab shell."
  (interactive "r")
  (if (> beg end) (let (mid) (setq mid beg beg end end mid)))
  (let ((command (let ((str (concat (buffer-substring-no-properties beg end)
 				    "\n")))
 		   (while (string-match "\n\\s-*\n" str)
 		     (setq str (concat (substring str 0 (match-beginning 0))
 				       "\n"
 				       (substring str (match-end 0)))))
 		   str))
 	(msbn (matlab-shell-buffer-barf-not-running))
 	(lastcmd))
    (save-excursion
      (set-buffer msbn)
      (if (not (matlab-on-prompt-p))
 	  (error "Matlab shell must be non-busy to do that"))
      ;; Save the old command
      (beginning-of-line)
      (re-search-forward comint-prompt-regexp)
      (setq lastcmd (buffer-substring (point) (matlab-point-at-eol)))
      (delete-region (point) (matlab-point-at-eol))
      ;; We are done error checking, run the command.
      (comint-send-string (get-buffer-process (current-buffer)) command)
      (insert lastcmd))
    (set-buffer msbn)
    (goto-char (point-max))
    (display-buffer msbn)
    ))
 
(defun matlab-on-prompt-p ()
  "Return t if we Matlab can accept input."
  (save-excursion
    (goto-char (point-max))
    (beginning-of-line)
    (looking-at comint-prompt-regexp)))

(defun matlab-on-empty-prompt-p ()
  "Return t if we Matlab is on an empty prompt."
  (save-excursion
    (goto-char (point-max))
    (beginning-of-line)
    (looking-at (concat comint-prompt-regexp "\\s-*$"))))

(defun matlab-shell-buffer-barf-not-running ()
  "Return a running Matlab buffer iff it is currently active."
  (or (matlab-shell-active-p)
      (error "You need to run the command `matlab-shell' to do that!")))
  

(defun matlab-shell-collect-command-output (command)
  "If there is a Matlab shell, run the Matlab COMMAND and return it's output.
It's output is returned as a string with no face properties.  The text output
of the command is removed from the Matlab buffer so there will be no
indication that it ran."
  (let ((msbn (matlab-shell-buffer-barf-not-running))
	(pos nil)
	(str nil)
	(lastcmd))
    (save-excursion
      (set-buffer msbn)
      (if (not (matlab-on-prompt-p))
	  (error "Matlab shell must be non-busy to do that"))
      ;; Save the old command
      (goto-char (point-max))
      (beginning-of-line)
      (re-search-forward comint-prompt-regexp)
      (setq lastcmd (buffer-substring (point) (matlab-point-at-eol)))
      (delete-region (point) (matlab-point-at-eol))
      ;; We are done error checking, run the command.
      (setq pos (point))
      (comint-send-string (get-buffer-process (current-buffer))
			  (concat command "\n"))
      (message "Matlab ... Executing command.")
      (goto-char (point-max))
      (while (or (>= pos (point)) (not (matlab-on-empty-prompt-p)))
	(accept-process-output (get-buffer-process (current-buffer)))
	(goto-char (point-max))
	(message "Matlab reading..."))
      (message "Matlab reading...done")
      (save-excursion
	(goto-char pos)
	(beginning-of-line)
	(setq str (buffer-substring-no-properties (save-excursion
						    (goto-char pos)
						    (beginning-of-line)
						    (forward-line 1)
						    (point))
						  (save-excursion
						    (goto-char (point-max))
						    (beginning-of-line)
						    (point))))
	(delete-region pos (point-max)))
      (insert lastcmd))
    str))

(defvar matlab-shell-save-and-go-history '("()")
  "Keep track of parameters passed to the Matlab shell.")

(defun matlab-shell-save-and-go ()
  "Save this M file, and evaluate it in a Matlab shell."
  (interactive)
  (if (not (eq major-mode 'matlab-mode))
      (error "Save and go is only useful in a Matlab buffer!"))
  (let ((fn-name (file-name-sans-extension
		  (file-name-nondirectory (buffer-file-name))))
	(msbn (concat "*" matlab-shell-buffer-name "*"))
	(param ""))
    (save-buffer)
    ;; Do we need parameters?
    (if (save-excursion
	  (goto-char (point-min))
	  (end-of-line)
	  (forward-sexp -1)
	  (looking-at "([a-zA-Z]"))
	(setq param (read-string "Parameters: "
				 (car matlab-shell-save-and-go-history)
				 'matlab-shell-save-and-go-history)))
    ;; No buffer?  Make it!
    (if (not (get-buffer msbn)) (matlab-shell))
    ;; Ok, now fun the function in the matlab shell
    (if (get-buffer-window msbn t)
	(select-window (get-buffer-window msbn t))
      (switch-to-buffer (concat "*" matlab-shell-buffer-name "*")))
    (comint-send-string (get-buffer-process (current-buffer))
			(concat fn-name " " param "\n"))))

(defun matlab-shell-last-error ()
  "In the Matlab interactive buffer, find the last Matlab error, and go there.
To reference old errors, put the cursor just after the error text."
  (interactive)
  (let (eb el)
    (save-excursion
      (if (not (re-search-backward gud-matlab-error-regexp nil t))
	  (error "No errors found!"))
      (setq eb (buffer-substring-no-properties
		(match-beginning 2) (match-end 2))
	    el (buffer-substring-no-properties
		(match-beginning 3) (match-end 3))))
    (find-file-other-window eb)
    (goto-line (string-to-int el))))

(defun matlab-shell-dbstop-error ()
  "Stop on errors."
  (interactive)
  (comint-send-string (get-buffer-process (current-buffer))
		      "dbstop if error\n"))

(defun matlab-shell-dbclear-error ()
  "Don't stop on errors."
  (interactive)
  (comint-send-string (get-buffer-process (current-buffer))
		      "dbclear if error\n"))

(defun matlab-shell-demos ()
  "Matlab demos."
  (interactive)
  (comint-send-string (get-buffer-process (current-buffer)) "demo\n"))

(defun matlab-shell-close-figures ()
  "Close any open figures."
  (interactive)
  (comint-send-string (get-buffer-process (current-buffer)) "close all\n"))

(defun matlab-shell-close-current-figure ()
  "Close current figure."
  (interactive)
  (comint-send-string (get-buffer-process (current-buffer)) "delete(gcf)\n"))

(defun matlab-shell-exit ()
  "Exit Matlab shell."
  (interactive)
  (comint-send-string (get-buffer-process (current-buffer)) "exit\n")
  (kill-buffer nil))

;;; matlab-shell based Topic Browser and Help =================================

(defcustom matlab-shell-topic-mode-hook nil
  "*Matlab shell topic hook."
  :group 'matlab-shell
  :type 'hook)

(defvar matlab-shell-topic-current-topic nil
  "The currently viewed topic in a Matlab shell topic buffer.")

(defun matlab-shell-topic-browser ()
  "Create a topic browser by querying an active Matlab shell using HELP.
Maintain state in our topic browser buffer."
  (interactive)
  ;; Reset topic browser if it doesn't exist.
  (if (not (get-buffer "*Matlab Topic*"))
      (setq matlab-shell-topic-current-topic nil))
  (let ((b (get-buffer-create "*Matlab Topic*")))
    (switch-to-buffer b)
    (if (string= matlab-shell-topic-current-topic "")
	nil
      (matlab-shell-topic-mode)
      (matlab-shell-topic-browser-create-contents ""))))

(defvar matlab-shell-topic-mouse-face-keywords
  '(;; These are subtopic fields...
    ("^\\(\\w+/\\w+\\)[ \t]+-" 1 font-lock-reference-face)
    ;; These are functions...
    ("^[ \t]+\\(\\w+\\)[ \t]+-" 1 font-lock-function-name-face)
    ;; Here is a See Also line...
    ("[ \t]+See also "
     ("\\(\\w+\\)\\([,.]\\| and\\|$\\) *" nil nil (1 font-lock-reference-face))))
  "These are keywords we also want to put mouse-faces on.")

(defvar matlab-shell-topic-font-lock-keywords
  (append matlab-shell-topic-mouse-face-keywords
	  '(("^[^:\n]+:$" 0 font-lock-keyword-face)
	    ;; These are subheadings...
	    ("^[ \t]+\\([^.\n]+[a-zA-Z.]\\)$" 1 'underline)
	    ))
  "Keywords useful for highlighting a Matlab TOPIC buffer.")

(defvar matlab-shell-help-font-lock-keywords
  (append matlab-shell-topic-mouse-face-keywords
	  '(;; Function call examples
	    ("[ \t]\\([A-Z]+\\)\\s-*=\\s-*\\([A-Z]+[0-9]*\\)("
	     (1 font-lock-variable-name-face)
	     (2 font-lock-function-name-face))
	    ("[ \t]\\([A-Z]+[0-9]*\\)("
	     (1 font-lock-function-name-face))
	    ;; Parameters: Not very accurate, unfortunately.
	    ("[ \t]\\([A-Z]+[0-9]*\\)("
	     ("'?\\(\\w+\\)'?\\([,)]\\) *" nil nil
	      (1 font-lock-variable-name-face))
	     )
	    ;; Reference uppercase words
	    ("\\<\\([A-Z]+[0-9]*\\)\\>" 1 font-lock-reference-face)))
  "Keywords for regular help buffers.")

;; View-major-mode is an emacs20 thing.  This gives us a small compatibility
;; layer.
(if (not (fboundp 'view-major-mode)) (defalias 'view-major-mode 'view-mode))

(define-derived-mode matlab-shell-help-mode
  view-major-mode "M-Help"
  "Major mode for viewing Matlab help text.
Entry to this mode runs the normal hook `matlab-shell-help-mode-hook'.

Commands:
\\{matlab-shell-help-mode-map}"
  (make-local-variable 'font-lock-defaults)
  (setq font-lock-defaults '((matlab-shell-help-font-lock-keywords)
			     t nil ((?_ . "w"))))
  ;; This makes sure that we really enter font lock since
  ;; kill-all-local-variables is not used by old view-mode.
  (and (boundp 'global-font-lock-mode) global-font-lock-mode
       (not font-lock-mode) (font-lock-mode 1))
  (easy-menu-add matlab-shell-help-mode-menu matlab-shell-help-mode-map)
  (matlab-shell-topic-mouse-highlight-subtopics)
  )

(define-key matlab-shell-help-mode-map [return] 'matlab-shell-topic-choose)
(define-key matlab-shell-help-mode-map "t" 'matlab-shell-topic-browser)
(define-key matlab-shell-help-mode-map "q" 'bury-buffer)
(define-key matlab-shell-help-mode-map
  [(control h) (control m)] matlab-help-map)
(if (string-match "XEmacs" emacs-version)
    (define-key matlab-shell-help-mode-map [button2] 'matlab-shell-topic-click)
  (define-key matlab-shell-help-mode-map [mouse-2] 'matlab-shell-topic-click))

(easy-menu-define
 matlab-shell-help-mode-menu matlab-shell-help-mode-map
 "Matlab shell topic menu"
 '("Matlab Help"
   ["Describe This Command" matlab-shell-topic-choose t]
   "----"
   ["Describe Command" matlab-shell-describe-command t]
   ["Describe Variable" matlab-shell-describe-variable t]
   ["Command Apropos" matlab-shell-apropos t]
   ["Topic Browser" matlab-shell-topic-browser t]
   "----"
   ["Exit" bury-buffer t]))

(define-derived-mode matlab-shell-topic-mode
  matlab-shell-help-mode "M-Topic"
  "Major mode for browsing Matlab HELP topics.
The output of the Matlab command HELP with no parameters creates a listing
of known help topics at a given installation.  This mode parses that listing
and allows selecting a topic and getting more help for it.
Entry to this mode runs the normal hook `matlab-shell-topic-mode-hook'.

Commands:
\\{matlab-shell-topic-mode-map}"
  (setq font-lock-defaults '((matlab-shell-topic-font-lock-keywords)
			     t t ((?_ . "w"))))
  (if (string-match "XEmacs" emacs-version)
      (setq mode-motion-hook 'matlab-shell-topic-highlight-line))
  (easy-menu-add matlab-shell-topic-mode-menu matlab-shell-topic-mode-map)
  )

(easy-menu-define
 matlab-shell-topic-mode-menu matlab-shell-topic-mode-map
 "Matlab shell topic menu"
 '("Matlab Topic"
   ["Select This Topic" matlab-shell-topic-choose t]
   ["Top Level Topics" matlab-shell-topic-browser t]
   "----"
   ["Exit" bury-buffer t]))

(defun matlab-shell-topic-browser-create-contents (subtopic)
  "Fill in a topic browser with the output from SUBTOPIC."
  (toggle-read-only -1)
  (erase-buffer)
  (insert (matlab-shell-collect-command-output (concat "help " subtopic)))
  (goto-char (point-min))
  (forward-line 1)
  (delete-region (point-min) (point))
  (setq matlab-shell-topic-current-topic subtopic)
  (if (not (string-match "XEmacs" emacs-version))
      (matlab-shell-topic-mouse-highlight-subtopics))
  (toggle-read-only 1)
  )

(defun matlab-shell-topic-click (e)
  "Click on an item in a Matlab topic buffer we want more information on.
Must be bound to event E."
  (interactive "e")
  (mouse-set-point e)
  (matlab-shell-topic-choose))

(defun matlab-shell-topic-choose ()
  "Choose the topic to expand on that is under the cursor.
This can fill the topic buffer with new information.  If the topic is a
command, use `matlab-shell-describe-command' instead of changing the topic
buffer."
  (interactive)
  (let ((topic nil) (fun nil) (p (point)))
    (save-excursion
      (beginning-of-line)
      (if (looking-at "^\\w+/\\(\\w+\\)[ \t]+-")
	  (setq topic (match-string 1))
	(if (looking-at "^[ \t]+\\(\\(\\w\\|_\\)+\\)[ \t]+-")
	    (setq fun (match-string 1))
	  (if (and (not (looking-at "^[ \t]+See also"))
		   (not (save-excursion (forward-char -2)
					(looking-at ",$"))))
	      (error "You did not click on a subtopic, function or reference")
	    (goto-char p)
	    (forward-word -1)
	    (if (not (looking-at "\\(\\(\\w\\|_\\)+\\)\\([.,]\\| and\\|\n\\)"))
		(error "You must click on a reference")
	      (setq topic (match-string 1)))))))
    (message "Opening item %s..." (or topic fun))
    (if topic
	(matlab-shell-topic-browser-create-contents (downcase topic))
      (matlab-shell-describe-command fun))
    ))

(defun matlab-shell-topic-mouse-highlight-subtopics ()
  "Put a `mouse-face' on all clickable targets in this buffer."
  (save-excursion
    (let ((el matlab-shell-topic-mouse-face-keywords))
      (while el
	(goto-char (point-min))
	(while (re-search-forward (car (car el)) nil t)
	  (let ((cd (car (cdr (car el)))))
	    (if (numberp cd)
		(put-text-property (match-beginning cd) (match-end cd)
				   'mouse-face 'highlight)
	      (while (re-search-forward (car cd) nil t)
		(put-text-property (match-beginning (car (nth 3 cd)))
				   (match-end (car (nth 3 cd)))
				   'mouse-face 'highlight)))))
	(setq el (cdr el))))))

(defun matlab-shell-topic-highlight-line (event)
  "A value of `mode-motion-hook' which will highlight topics under the mouse.
EVENT is the user mouse event."
  (let* ((buffer (event-buffer event))
	 (point (and buffer (event-point event))))
    (if (and buffer (not (eq buffer mouse-grabbed-buffer)))
	(save-excursion
	  (save-window-excursion
	    (set-buffer buffer)
	    (mode-motion-ensure-extent-ok event)
	    (if (not point)
		(detach-extent mode-motion-extent)
	      (goto-char point)
	      (end-of-line)
	      (setq point (point))
	      (beginning-of-line)
	      (if (or (looking-at "^\\w+/\\(\\w+\\)[ \t]+-")
		      (looking-at "^[ \t]+\\(\\(\\w\\|_\\)+\\)[ \t]+-"))
		  (set-extent-endpoints mode-motion-extent (point) point)
		(detach-extent mode-motion-extent))))))))


;;; M File path stuff =========================================================

(defun matlab-mode-determine-mfile-path ()
  "Create the path in `matlab-mode-install-path'."
  (let ((path (file-name-directory matlab-shell-command)))
    ;; if we don't have a path, find the Matlab executable on our path.
    (if (not path)
	(let ((pl exec-path))
	  (while (and pl (not path))
	    (if (and (file-exists-p (concat (car pl) "/" matlab-shell-command))
		     (not (car (file-attributes (concat (car pl) "/"
							matlab-shell-command)))))
		(setq path (car pl)))
	    (setq pl (cdr pl)))))
    (if (not path)
	nil
      ;; When we find the path, we need to massage it to identify where
      ;; the M files are that we need for our completion lists.
      (if (string-match "/bin$" path)
	  (setq path (substring path 0 (match-beginning 0))))
      ;; Everything stems from toolbox (I think)
      (setq path (concat path "/toolbox/")))
    path))

(defcustom matlab-mode-install-path (list (matlab-mode-determine-mfile-path))
  "Base path pointing to the locations of all the m files used by matlab.
All directories under each element of `matlab-mode-install-path' are
checked, so only top level toolbox directories need be added."
  :group 'matlab-shell
  :type '(repeat (string :tag "Path: ")))

(defun matlab-find-file-under-path (path filename)
  "Return the pathname or nil of PATH under FILENAME."
  (if (file-exists-p (concat path filename))
      (concat path filename)
    (let ((dirs (directory-files path t nil t))
	  (found nil))
      (while (and dirs (not found))
	(if (and (car (file-attributes (car dirs)))
		 ;; don't redo our path names
		 (not (string-match "/\\.\\.?$" (car dirs)))
		 ;; don't find files in object directories.
		 (not (string-match "@" (car dirs))))
	    (setq found
		  (matlab-find-file-under-path (concat (car dirs) "/")
					       filename)))
	(setq dirs (cdr dirs)))
      found)))

(defun matlab-find-file-on-path (filename)
  "Find FILENAME on the current Matlab path.
The Matlab path is determined by `matlab-mode-install-path' and the
current directory.  You must add user-installed paths into
`matlab-mode-install-path' if you would like to have them included."
  (interactive
   (list
    (let ((default (save-excursion
		     (if (or (bolp)
			     (looking-at "\\s-")
			     (save-excursion (forward-char -1)
					     (looking-at "\\s-")))
			 nil
		       (forward-word -1))
		     (matlab-navigation-syntax
		       (if (looking-at "\\sw+\\>")
			   (match-string 0))))))
      (if default
	  (let ((s (read-string (concat "File (default " default "): "))))
	    (if (string= s "") default s))
	(read-string "File: ")))))
  (if (string= filename "")
      (error "You must specify an M file"))
  (if (not (string-match "\\.m$" filename))
      (setq filename (concat filename ".m")))
  (let ((fname nil)
	(dirs matlab-mode-install-path))
    (if (file-exists-p (concat default-directory filename))
	(setq fname (concat default-directory filename)))
    (while (and (not fname) dirs)
      (if (stringp dirs)
	  (progn
	    (message "Searching for %s in %s" filename (car dirs))
	    (setq fname (matlab-find-file-under-path (car dirs) filename))))
      (setq dirs (cdr dirs)))
    (if fname (find-file fname)
      (error "File %s not found on any known paths.  \
Check `matlab-mode-install-path'" filename))))

(defun matlab-find-file-click (e)
  "Find the file clicked on with event E on the current path."
  (interactive "e")
  (mouse-set-point e)
  (let ((f (save-excursion
	     (if (or (bolp)
		     (looking-at "\\s-")
		     (save-excursion (forward-char -1)
				     (looking-at "\\s-")))
		 nil
	       (forward-word -1))
	     (matlab-navigation-syntax
	       (if (looking-at "\\sw+\\>")
		   (match-string 0))))))
    (if (not f) (error "To find an M file, click on a word"))
    (matlab-find-file-on-path f)))


;;; matlab-mode debugging =====================================================

(defun matlab-show-line-info ()
  "Display type and attributes of current line.  Used in debugging."
  (interactive)
  (let ((msg "line-info:") (deltas (matlab-calc-deltas)))
    ;(if (matlab-lattr-semantics)
    ;(setq msg (concat msg (format "%S" (matlab-lattr-semantics)))))
    (cond
     ((matlab-ltype-empty)
      (setq msg (concat msg " empty")))
     ((matlab-ltype-comm)
      (setq msg (concat msg " comment")))
     (t
      (setq msg (concat msg " code"))))
    (setq msg (concat msg " add-from-prev="
		      (int-to-string (car deltas))))
    (setq msg (concat msg " add-to-next="
		      (int-to-string (car (cdr deltas)))))
    (setq msg (concat msg " indent="
		      (int-to-string (matlab-calc-indent))))
    (if (matlab-lattr-cont)
	(setq msg (concat msg " w/cont")))
    (if (matlab-lattr-comm)
	(setq msg (concat msg " w/comm")))
    (message msg)))

(provide 'matlab)

;;; Change log
;; 03Jun98 by Eric Ludlam <eludlam@mathworks.com>
;;      `matlab-unterminated-string-face' is now a self-referencing variable.
;;      Post version 2.1.1
;;
;; 02Jun98 by Eric Ludlam <eludlam@mathworks.com>
;;      Fixed the function `matlab-mode-determine-mfile-path' to not fail.
;;      Updated `matlab-find-file-on-path' to handle nil's in the list
;;         and provide helpful errors
;;
;; 01Jun98 by Eric Ludlam <eludlam@mathworks.com>
;;      Post version 2.1
;;
;; 27May98 by Eric Ludlam <eludlam@mathworks.com>
;;      Enabled `matlab-mode-determine-mfile-path' and used it to
;;        define the variable `matlab-mode-install-path'.  This is
;;        then used by the new commands `matlab-find-file-on-path' and
;;        `matlab-find-file-click'  Added these to the keymap and meny.
;;
;; 22May98 by Dan Nicolaescu <done@wynken.ece.arizona.edu>
;;      Fixed derived modes to correctly font lock upon creation.
;;
;; 19May98 by Peter J. Acklam <jacklam@math.uio.no>
;;      New function highlighting regexps which are more accurate.
;;
;; 11May98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Ran new checkdoc on the file and fixed all calls to `error'
;;
;; 11May98 by Peter J. Acklam <jacklam@math.uio.no>
;;      Fixed a string highlighting bug.
;;
;; 11May98 Michael Granzow <mg@medi.physik.uni-oldenburg.de>
;;      Found bug in `matlab-keywords-boolean'.
;;
;; 08May98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      CR after unterminated END will error, but still insert the CR.
;;
;; 08May98 by Hubert Selhofer <hubert@na.mathematik.uni-tuebingen.de>
;;      CR when (point) == (point-min) no longer errors
;;
;; 05May98 by Hubert Selhofer <hubert@na.mathematik.uni-tuebingen.de>
;;      Many spelling fixes in comments, and doc strings.
;;      Adjusted some font-lock keywords to be more compact/effecient.
;;
;; 30Apr98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      %endfunction unindenting can now have arbitrary text after it.
;;
;; 24Apr98 by Peter J. Acklam <jacklam@math.uio.no>
;;      Fixed highlighting of for statements w/ traling comments.
;;
;; 23Apr98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Fixed -vf-block functions to have more restrictive before-keyword
;;        so we don't accidentally match keywords at the end of symbols.
;;
;; 22Apr98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Release 2.0 to web site and newsgroups.
;;      Ran checkdoc/ispell on entire file.
;;      Cleaned up some compile-time warnings.
;;      Verified XEmacs compatibility.
;;
;; 13Apr98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Fixed bug in `matlab-mode-vf-functionname' to prevent infinite loop
;;        on empty files.
;;
;; 10Apr98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Added break to highlighted keywords.
;;      Case variable highlighting now stops at comment endings.
;;
;; 07Apr98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      `matlab-ltype-comm' no longer demands a space after the %.
;;      Indentor now unindents the comment %endfunction.
;;      Removed transposing transpose part.  It broke quoted quotes.
;;
;; 02Apr98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Comments appearing at the end of a function, and just before a new
;;          subfunction, are now unintented if `matlab-indent-function' is
;;          non-nil.  This lets matlab users use %endfunction at the end
;;          of a function, and get the indentation right.
;;
;; 01Apr98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Smarter font lock for case (jacklam@math.uio.no)
;;      Auto fill accounts for chars inserted based on the variable
;;          `matlab-fill-count-ellipsis-flag'.
;;      Auto fill will now fill a string by putting it into brackets
;;          controlled by `matlab-fill-strings-flag'.
;;
;; 18Mar98 by Peter J. Acklam <jacklam@math.uio.no>
;;      Enabled multi-line function definitions in font-lock and imenu.
;;
;; 16Mar98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Fixed potential error in comment searching around ...
;;      Fixed many function regexp's as per Peter J. Acklam's
;;          <jacklam@math.uio.no> suggestion.
;;
;; 09Mar98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Fixed `tempo-template-matlab-function' to work correctly.
;;      Fixed indentation for many other templates.
;;      Made sure the verifier uses navigation syntax.
;;
;; 23Feb98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Fixed problem with x='%'    % ' this shouldn't work
;;      Fixed a problem w/ strung up brackets messing up valid
;;         end identification.
;;
;; 17Feb98 by Aki Vehtari <Aki.Vehtari@hut.fi>
;;      Fixed prompt regexp to include the debugging K.
;;
;; 11Feb98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Made `matlab-mode-vf-functionname' more robust to arbitrary
;;         versions of a function definition.  This includes allowing
;;         comments and blank lines before the first fn definition.
;;      Fixed up the font lock keywords for functions some
;;
;; 10Feb98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Fixed problem with derived view mode.
;;      Fixed font locking of globals to allow a ; at the end.
;;      Fixed function name verifier to not allow = on next line.
;;         It used to match invalid expressions.
;;      `matlab-shell-collect-command-output' now uses a different prompt
;;         detector when waiting for output.  This prevents early exit.
;;
;; 09Feb98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Updated `matlab-indent-line' to not edit the buffer if no changes
;;         are needed, and to make after cursor position smarter.
;;
;; 05Feb98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Added completion semantics and lists for HandleGraphics property lists
;;      Added `matlab-completion-technique' and made it's default value
;;         'completion.  This shows a buffer of completions instead of
;;         cycling through them as the hippie-expand command does.
;;
;; 26Jan98 by Aki Vehtari <Aki.Vehtari@hut.fi>
;;      The Matlab logo variable now uses XEmacs 20.4 locate function.
;;      Small cleanups
;;
;; 26Jan98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Updated `matlab-fill-paragraph' to use a better fill prefix.
;;      Moved code sections around, and added page breaks for navigation.
;;
;; 23Jan98 by Aki Vehtari <Aki.Vehtari@hut.fi>
;;	(matlab-frame-init): Fix typo in menu.
;;	(matlab-output-to-temp-buffer): Use matlab-shell-help-mode.
;;	(matlab-shell-run-region): New function.
;;	(matlab-shell-collect-command-output): Remove (goto-char (point-max)).
;;	(matlab-shell-topic-mode-hook): Name change.
;;	(matlab-shell-topic-browser): Use matlab-shell-topic-mode.
;;	(matlab-shell-help-mode): New mode. Derive from view-major-mode.
;;	(matlab-shell-help-mode-menu): Define.
;;	(matlab-shell-topic-mode): Name change and derive from
;;	   matlab-shell-help-mode.
;;	(matlab-shell-topic-mode-menu): Name change.
;;
;; 22Jan98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Make `matlab-comment' insert `matlab-comment-s' on lines with
;;         no text when there there is no previous comment line to mimic.
;;
;; 21Jan98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Fixed a few templates.  Added `matlab-if-else'.
;;      `matlab-insert-end-block' will now add a comment consisting of
;;         the text starting the block being ended.
;;      Added colors to variables defined with the global command.
;;      Added `matlab-complete-symbol' which uses `matlab-find-recent-variable'
;;         which searches backwards for variables names, and
;;         `matlab-find-user-functions' which finds user functions.
;;         There are also `matlab-*-completions' for solo commands
;;         (if, else, etc), value commands, and boolean commands.
;;         The current semantic state is found w/ `matlab-lattr-semantics'
;;
;; 20Jan98 by Eric M. Ludlam <eludlam@mathworks.com>
;;     Changed `matlab-block-scan-re' to have a limiting expression at
;;         the beginning.  This makes sexp scanning faster by skipping
;;         more semantically bad matches.
;;     Forward/backward sexp now watch `matlab-scan-on-screen-only', which
;;         make them stop when the scan falls off the screen.  Useful for
;;         making the block highlighter *much* faster for large constructs,
;;         and is logical since we can't see the highlight anyway.
;;     Added `matlab-block-verify-max-buffer-size' to turn off long checks
;;         on big buffers during save only.  Requesting a verify will do
;;         the checks anyway.
;;     Fixed block verifiers to check that found end keywords are also
;;         valid block terminators.
;;
;; 19Jan98 by Eric M. Ludlam <eludlam@mathworks.com>
;;     Fixed `gud-matlab-marker-filter' and `matlab-join-comment-lines'
;;         to not use `replace-match's fifth argument.
;      Replaced `matlab-insert-' with tempo templates where appropriate.
;;
;; 19Jan98 by Aki Vehtari <Aki.Vehtari@hut.fi>
;;      Fixed `matlab-mode-vf-functionname' to use a correct form
;;         of `replace-match' for XEmacs.
;;      Suggested form of `matlab-navigation-syntax'.
;;
;; 14Jan98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Added manu `matlab-insert-' functions, including:
;;        `switch-block', `next-case', `end-block', `if-block',
;;        `for-block', `try-block', `while-block'.
;;      Added `matlab-stringify-region' which takes a region, and
;;        converts it to a string by adding ' around it, and quoting
;;        all the quotes in the region.
;;      Added an insertion prefix C-c C-c for all insert commands, and
;;        the stringify function.
;;      `matlab-auto-fill' is now assigned to `normal-auto-fill-function',
;;        which is an Emacs 20 thing for auto-fill minor mode.
;;      Added `matlab-beginning-of-command' and `end-of-command' which
;;        moves across lines w/ continuation.
;;      Changed `matlab-lattr-cont' to allow continuation on lines
;;        ending in semicolon.  Is this correct?
;;      Changed the main menu to have submenues for navigation,
;;        formatting, and the new insert functions.
;;      Fixed `matlab-forward-sexp' to not skip over brackets which
;;        was appeared to be a missunderstanding.
;;      Block highlighter and block verifiers no longer treat function
;;        as requiring an "end" keyword.
;;
;; 09Jan98 by Eric M. Ludlam <eludlam@mathworks.com>
;;      Based on code donated by Driscoll Tobin A <tad@cauchy.colorado.edu>
;;        `matlab-fill-paragraph' designed for M file help text, which
;;        will fill/justify comment text, and uses paragraph rules.
;;        `matlab-fill-comment-line' does not know about paragraphs.
;;      `matlab-cursor-in-string' can now take an optional argument
;;        which will identify an unterminated string.
;;      `matlab-auto-fill' will not fill strings, and if the string is
;;        not yet terminated, will also not fill it.  When the string
;;        is terminated, the split will happen after the string, even
;;        if it occurs after the `fill-column'.
;;
;; 08Jan98 by Aki Vehtari  <Aki.Vehtari@hut.fi>
;;      XEmacs compatibility associated with timers.
;;      XEmacs optimizations associated with point-at-[eb]ol.
;;      Turned key sequences from strings to Emacs/XEmacs wide [()] form
;;      Documentation string fixes.
;;      Customizable hooks.  Also update other custom vars.
;;      Remove `matlab-reset-vars' and turn variables controlled by
;;        `matlab-indent-function' into functions.
;;      Some menu re-arrangements & topic-browser menu.
;;      Use matlab-region-face instead of 'region when highlighting stuff.
;;      `matlab-shell-exit' now deletes the buffer when it's done.
;;      `write-contents-hooks' is forced buffer local.
;;      Fixed `matlab-output-to-temp-buffer'.
;;      Made matlab-shell group.
;;
;; 07Jan98 by Eric Ludlam <eludlam@mathworks.com>
;;      Fixed indenting problem when end is first used as matrix index
;;        and is also the first word on a line.
;;
;; 07Jan98 by Aki Vehtari  <Aki.Vehtari@hut.fi>
;;      Fixed comments to use add-hook instead of setq.
;;      Variable name cleanup.  Added ###autoload tags to -mode and -shell.
;;      Removed some unused variables.
;;
;; 24Dec97 by Eric Ludlam <eludlam@mathworks.com>
;;      Added `matlab-shell-enable-gud-flag' to control if the GUD features
;;        are used in shell mode or not.  This is automatically set to nil
;;        when certain GUD features are not present
;;      Added stop/clear if error to menu to help people out w/ the debugger.
;;      Added block highlighting of if/for/etc/end constructs.
;;      Fixed up cursor-in-string even more to handle bol better.
;;      Fixed problem w/ syntax table installing itself in funny places
;;        and fixed the fact that tab was now treated as whitespace.
;;
;; 22Dec97 by Eric Ludlam <eludlam@mathworks.com>
;;      Added verify/fix mode when saving.  Added function name check.
;;        Added unterminated block check.  Added unmatched end check.
;;      Fixed `matlab-backward-sexp' to error on mismatched end/begin blocks.
;;
;; 15Dec97 by Eric Ludlam <eludlam@mathworks.com>
;;      Fixed some string stuff, and added checks when starting the shell.
;;
;; 10Dec97 by Eric Ludlam <eludlam@mathworks.com>
;;      Fixed string font-locking based on suggestions from:
;;        Hubert Selhofer <hubert@na.uni-tuebingen.de>
;;        Peter John Acklam <jacklam@math.uio.no>
;;        Tim Toolan <toolan@ele.uri.edu>
;;      Fixed comment with ... indenting next line.
;;      Made command output collecting much faster.
;;
;; 10Dec97 merged the following:
;; 21May97 by Alf-Ivar Holm <alfh@ifi.uio.no>
;;      Added smart initial values of matlab help commands.
;;      Running commands in matlab-shell remembers old cmd line
;;      Commands can be run when a parial command line is waiting
;;      Changed apropo to apropos where applicable.
;;
;; 9Dec98 merged the following:
;; 30May97 by Hubert Selhofer <hubert@na.uni-tuebingen.de>
;;      Added 'endfunction' to keyword patterns (octave), slightly
;;          changed regexp for better performance.
;;      Added 'endfunction' to `matlab-block-end-pre-no-if' for compliance
;;          with octave.
;;      Fixed `matlab-clear-vars' (symbol names were incorrectly
;;           spelled matlab-matlab-*).
;;      Fixed typo in `matlab-really-gaudy-font-lock-keywords'.
;;
;; 26Nov97 by Eric Ludlam <eludlam@mathworks.com>
;;      Added support for cell array indenting/continuation.
;;      Begin re-enumeration to V 2.0
;;
;; 11Nov97 by Eric Ludlam <eludlam@mathworks.com>
;;      Added custom support for [X]emacs 20.
;;
;; 11Nov97 by Eric Ludlam <eludlam@mathworks.com>
;;      Added beginning/end-defun navigation functions.
;;      Ran through latest version of checkdoc for good doc strings.
;;
;; 04Sep97 by Eric Ludlam <eludlam@mathworks.com>
;;      Added try/catch blocks which are new Matlab 5.2 keywords.
;;
;; 02Sep97 by Eric Ludlam <eludlam@mathworks.com>
;;      Made auto-fill mode more robust with regard to comments
;;        at the end of source lines
;;
;; 13Aug97 by Eric Ludlam <eludlam@mathworks.com>
;;      Fixed indentation bugs regarding the beginning of buffer.
;;      Added GUD support into matlab-shell.  Debugger commands will
;;        now automatically check the stack and post the files being
;;        examined via this facility.
;;
;; 26Jun97 by Eric Ludlam <eludlam@mathworks.com>
;;      Help/Apropo buffers are now in Topic mode, and are highlighted.
;;        This allows navigation via key-clicks through the help.
;;      Describe-command can find a default in the current M file.
;;      Mouse-face set to make clickable items mouse-sensitive in topic buffers
;;
;; 25Jun97 by Anders Stenman <stenman@isy.liu.se>
;;      Some XEmacs hacks. Implemented highlighting of subtopics and
;;      commands under mouse in topic-browser mode. Added a nice Matlab
;;      logo in matlab-shell mode.
;;      See: http://www.control.isy.liu.se/~stenman/matlab
;;
;; 13Jun97 by Anders Stenman <stenman@isy.liu.se>
;;      Use the easymenu package for menus. Works both in XEmacs and
;;      FSF Emacs. Bound TAB to comint-dynamic-complete-filename in
;;      matlab-shell mode. Added a function matlab-shell-process-filter
;;      to filter out some escape character rubbish from Matlab output.
;;
;; 20May97 by Matt Wette <mwette@alumni.caltech.edu>
;;	Released as version 1.10.0.
;;
;; 16May97 by Eric Ludlam <eludlam@mathworks.com>
;;      Ran through checkdoc to fix documentation strings.
;;
;; 15May97 by Matt Wette <mwette@alumni.caltech.edu>
;;	Added shell-mode-map bindings; run matlab-shell-mode-hook, not
;;	matlab-shell-mode-hooks (PMiller). Changed keymaps for \C-<letter>,
;;	which conflicted w/ emacs style guidelines.
;;
;; 08May97 by Eric Ludlam <eludlam@mathworks.com>
;;      Fixed forward/backward sexp error when end keyword appears as
;;            word component such as the symbol the_end
;;
;; 22Apr97 by Eric Ludlam <eludlam@mathworks.com>
;;      Fixed comment where `indent-function' was incorrectly spelled
;;      Fixed indentation when strings contained [] characters.
;;      Fixed indentation for multi-function files
;;      Added Imenu keywords.  Permits use w/ imenu and emacs/speedbar
;;      The actual version of matlab file is not in a variable
;;      Keybinding for forward/backward sexp
;;      New function finds the mfile path.  Not used for anything useful yet.
;;      Added matlab-shell/emacs io scripting functions.  Used this in
;;            a topic/help/apropo browser.  Could be used w/ other
;;            functions quite easily.
;;
;; 12Mar97 by Eric Ludlam <eludlam@mathworks.com>
;;      Added new `matlab-shell-collect-command-output' to use for running
;;            matlab commands and getting strings back.  Used this function
;;            to create `-describe-function', `-describe-variable', and
;;            `-apropo'.  Should be useful for other things too.
;;      Added some XEmacs specific stuff.
;;
;; 07Mar97 by Matt Wette <mwette@alumni.caltech.edu>
;;	Fixed a few xemacs problems.  Released as 1.09.0.
;;
;; 03Mar97 by Eric Ludlam <eludlam@mathworks.com>
;;      Added expressions to handle blocks which are not terminated with
;;            the 'end' command
;;      Added `matlab-shell-save-and-go' function to automatically run
;;            a function after saving it.
;;      Bug fixes to `matlab-forward-sexp'
;;      Improved font lock interface to take advantage of the user
;;            variable `font-lock-use-maximal-decoration'
;;
;; 24Feb97 by Eric Ludlam <eludlam@mathworks.com>
;;      Added more font locking, plus font locking of `matlab-shell'
;;      Added `matlab-backward-sexp',`matlab-cursor-in-string-or-comment'
;;      Added ability to indent switch/case/case/otherwise/end blocks
;;            as per manual specifications for matlab v5.0
;;      Added command for matlab-shell to goto the last reported error
;;      Modified matlab-shell to use comint features instead of hand
;;            crafted workarounds of the defaults
;;
;; 07Dec96 by Matt Wette <mwette@alumni.caltech.edu>
;;	incorporated many fixes from Mats Bengtsson <matsb@s3.kth.se>;
;;	font-lock comment/string fixes, Eric Ludlam <eludlam@mathworks.com>;
;;	added support for switch construct;
;;
;; 01Aug96 by Matt Wette <mwette@alumni.caltech.edu>
;;	fixed to jive w/ emacs lib conventions: changed name of file from
;;	matlab-mode.el to matlab.el (14 char limit); released as 1.08.0
;;
;; 28Apr96 by Matt Wette <mwette@alumni.caltech.edu>
;;	comments lines w/ just % are now hilighted; syntax table: "-2" changed
;;	to " 2"; released 1.07.6
;;
;; 30Jan96 by Matt Wette <mwette@alumni.caltech.edu>
;;	fixed problem w/ emacs-19.30 filling and auto-fill problem thanks to
;;	Mats Bengtsson <matsb@s3.kth.se>; started implementation of matlab-
;;	shell, based on comint and shell-mode; released 1.07.5
;;
;; 25Jan96 by Matt Wette <mwette@alumni.caltech.edu>
;;	added "global" to font-lock, hilit keywords; fixed indenting of 2nd
;;	line if first ends in ...; filling is broken for FSF19.30 (works for
;;	FSF19.28); torkel fixes to matlab-reset-vars; fixed indent bug
;;	reported by Trevor Cooper;
;;
;; 20Jan96 by Matt Wette <mwette@alumni.caltech.edu>
;;	cleaned up commenting; added preliminary `matlab-shell' mode,
;;	rel 1.07.4
;;
;; 19Jan96 by Matt Wette <mwette@alumni.caltech.edu>
;;	commented out `debug-on-error'; got hilit to work for sam
;;
;; 18Jan96 by Matt Wette <mwette@alumni.caltech.edu>
;;	fixed problem int `matlab-prev-line' which caused fatal `matlab-mode';
;;	crash fixed problem with indenting when keywords in comments; still
;;	haven't cleaned up comment formatting ...
;;
;; 21Jul95 by Matt Wette <mwette@alumni.caltech.edu>
;;	fixes by Bjorn Torkelsson <torkel@cs.umu.se>: replaced
;;	lattr-comment w/ lattr-comm to fix inconsistency; added
;;	function to font-lock keywords, added function name to
;;	`font-lock-function-name-face'.  He had also added function as
;;	a block begin keyword.  This should be an option since it will
;;	cause the body of a function to be indented.  Worked on
;;	filling.  More work on filling.  fixed many bugs reported by
;;	Rob Cunningham.  Pulled cadr.
;;
;; 13Jul95 by Matt Wette <mwette@mr-ed.jpl.nasa.gov>
;; 	changed indenting for continuation lines in calc-deltas to use
;;	cont-level; changed syntax-table;  changed the way the return key is
;;	mapped; released version 1.07.1
;;
;; 08Jul95 by Matt Wette <mwette@mr-ed.jpl.nasa.gov>
;;	This is a fairly major rewrite of the indenting functions to
;;	fix long- startednding problems arising from keywords and
;;	percents in strings.  We may have to add more heuristics later
;;	but this may work better.  Changed comment region string.
;;	Released version 1.07.0.
;;
;; 10Oct94 by Matt Wette <mwette@csi.jpl.nasa.gov>
;;	changed 'auto-fill-mode' to `auto-fill-function'; changed
;;	`comment-indent-' to `comment-indent-function'; fixed percents
;;	in strings being interpreted as comments, but a % for comment
;;	should not be followed by [disx%]
;;
;; 23Nov93 by Matt Wette <mwette@csi.jpl.nasa.gov>
;;	added Lucid emacs, GNU emacs font-lock and lhilit support; repaired
;;	mtlb-block-{beg,end}-kw (Thanks to Dave Mellinger <dkm1@cornell.edu>)
;;	removed string delim entry from matlab-mode-syntax-table (MATLAB lang
;;	sucks here -- why not use " for strings?).   Released vers 1.06.0
;;
;; 10Aug93 by Matt Wette <mwette@csi.jpl.nasa.gov>
;;	added `matlab-indent-end-before-return'; indent may be fixed now
;;	still not working for emacs 19
;;
;; 02Aug93 by Matt Wette <mwette@csi.jpl.nasa.gov>
;;	fixed error in `mtlb-calc-indent'; bumped version to 1.05.1;
;;	added `mtlb-prev-line'; bumped version to 1.05.3; added
;;	`mtlb-calc-block-indent'
;;
;; 01Aug93 by Matt Wette <mwette@csi.jpl.nasa.gov>
;;	Fixed bug which treated form as block-begin keyword.  Reworked
;;	`mtlb-calc-indent' -- seems to work better w/ redundant cont
;;	lines now. Bumbed version to 1.05.
;;
;; 13Jun93 by Matt Wette <mwette@csi.jpl.nasa.gov>
;;	Changed `linea' to `lattr', `linet' to `ltype', fixed
;;	Bumped version number from 1.03bb to 1.04.
;;
;; 02May91 by Matt Wette, mwette@csi.jpl.nasa.gov
;;	Added `matlab-auto-fill' for `auto-fill-hook' so that this
;;	mode doesn't try to fill matlab code, just comments.
;;
;; 22Apr91 by Matt Wette, mwette@csi.jpl.nasa.gov
;;	Changed `mtlb-ltype-cont' to `mtlb-lattr-cont',
;;	`mtlb-ltype-comment-on-line' to `mtlb-lattr-comment' and
;;	`mtlb-ltype-unbal-mexp' to `mtlb- attr-unbal-mext' to
;;	emphasize that these are line attributes and not line types.
;;	Modified `matlab-line-type' to reflect the change ini logic.
;;
;; 18Apr91 by Matt Wette, mwette@csi.jpl.nasa.gov
;;      Modified `matlab-comment-return' so that when hit on a line with a
;;	comment at the end it will go to the comment column.  To get the
;;	comment indented with the code, just hit TAB.
;;
;; 17Apr91 by Matt Wette, mwette@csi.jpl.nasa.gov
;;	Received critique from gray@scr.slb.com.  Changed ml- to mtlb-
;;	due to possible conflict with mlsupport.el routines.  Added
;;	`matlab-comment' -line-s and -on-line-s.  Fixed bug in
;;	`matlab-comment' (set-fill-prefix).  `matlab-comment-return'
;;	now works if called on a non-comment line.
;;
;; 04Mar91 by Matt Wette, mwette@csi.jpl.nasa.gov
;;	Added const `matlab-indent-before-return'.  Released Version 1.02.
;;
;; 02Feb91 by Matt Wette, mwette@csi.jpl.nasa.gov
;;	Changed names of `ml-*-line' to `ml-ltype-*'.  Cleaned up a
;;	lot. Added `ml-format-comment-line', fixed `ml-format-region'.
;;	Changed added "-s" on end of `matlab-comment-region' string.
;;	Justify needs to be cleaned up.
;;
;; Fri Feb  1 09:03:09 1991; gray@scr.slb.com
;;      Add function `matlab-comment-region', which inserts the string
;;      contained in the variable matlab-comment-region at the start
;;      of every line in the region.  With an argument the region is
;;      uncommented.  [Straight copy from fortran.el]
;;
;; 25Jan91 by Matt Wette, mwette@csi.jpl.nasa.gov
;;	Got indentation of matrix expression to work, I think.  Also,
;;	added tabs to comment start regular-expression.
;;
;; 14Jan91 by Matt Wette, mwette@csi.jpl.nasa.gov
;;	Added functions `ml-unbal-matexp' `ml-matexp-indent' for matrix
;;	expressions.
;;
;; 07Jan91 by Matt Wette, mwette@csi.jpl.nasa.gov
;;      Many changes.  Seems to work reasonably well.  Still would like
;;      to add some support for filling in comments and handle continued
;;      matrix expressions.  Released as Version 1.0.
;;
;; 04Jan91 by Matt Wette, mwette@csi.jpl.nasa.gov
;;      Created.  Used eiffel.el as a guide.

;;; matlab.el ends here
