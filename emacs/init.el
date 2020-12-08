(setq inhibit-startup-message t)
(setq inhibit-startup-echo-area-message t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(blink-cursor-mode -1)
(scroll-bar-mode -1)
(setq-default line-spacing 0.3)

(global-display-line-numbers-mode)
(xterm-mouse-mode)

;; Just a weird emacs/macOS required setting.
(setq dired-use-ls-dired nil)

;; Keep cursor at same position when scrolling.
(setq scroll-preserve-screen-position 1)

(defvar nhooyr-minor-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Scroll window up/down by one line.
    (define-key map (kbd "M-n") (kbd "C-u 2 C-v"))
    (define-key map (kbd "M-p") (kbd "C-u 2 M-v"))
    map)
  "nhooyr-minor-mode keymap.")

(define-minor-mode nhooyr-minor-mode
  "A minor mode so that my key settings override annoying major modes."
  :global t)

(nhooyr-minor-mode 1)

(ido-mode 1)
(setq ido-enable-flex-matching t)
(setq ido-everywhere t)
(load-theme 'manoj-dark t)
(set-face-attribute 'default nil :family "DejaVu Sans")
