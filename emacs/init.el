(menu-bar-mode -1)
(global-display-line-numbers-mode)

;; Keep cursor at same position when scrolling.
(setq scroll-preserve-screen-position 1)
;; Scroll window up/down by one line.
(global-set-key (kbd "M-n") (kbd "C-u 2 C-v"))
(global-set-key (kbd "M-p") (kbd "C-u 2 M-v"))
