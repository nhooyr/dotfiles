# Key bindings
# ------------
# Adapted from https://github.com/junegunn/fzf/blob/951746297e26159cd45501030c56eca4bea4e277/shell/key-bindings.fish
function fzf_key_bindings
  function fzf-history-widget -d "Show command history"
    set -q FZF_TMUX_HEIGHT; or set FZF_TMUX_HEIGHT 40%
    begin
      set -lx FZF_DEFAULT_OPTS "--height $FZF_TMUX_HEIGHT $FZF_DEFAULT_OPTS --tiebreak=index --bind=ctrl-r:toggle-sort $FZF_CTRL_R_OPTS +m"

      set -l FISH_MAJOR (echo $version | cut -f1 -d.)
      set -l FISH_MINOR (echo $version | cut -f2 -d.)

      # history's -z flag is needed for multi-line support.
      # history's -z flag was added in fish 2.4.0, so don't use it for versions
      # before 2.4.0.
      if [ "$FISH_MAJOR" -gt 2 -o \( "$FISH_MAJOR" -eq 2 -a "$FISH_MINOR" -ge 4 \) ];
        history -z | eval (__fzfcmd) --read0 -q '(commandline)' | perl -pe 'chomp if eof' | read -lz result
        and commandline -- $result
      else
        history | eval (__fzfcmd) -q '(commandline)' | read -l result
        and commandline -- $result
      end
    end
    commandline -f repaint
  end

  function __fzfcmd
    set -q FZF_TMUX; or set FZF_TMUX 0
    set -q FZF_TMUX_HEIGHT; or set FZF_TMUX_HEIGHT 40%
    if [ $FZF_TMUX -eq 1 ]
      echo "fzf-tmux -d$FZF_TMUX_HEIGHT"
    else
      echo "fzf"
    end
  end

  bind \cr fzf-history-widget

  if bind -M insert > /dev/null 2>&1
    bind -M insert \cr fzf-history-widget
  end
end
