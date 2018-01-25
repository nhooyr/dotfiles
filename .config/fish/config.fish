if status --is-interactive

  function preexec --on-event fish_preexec
    set -g preexec_time (date +%s)
  end

  function postexec --on-event fish_postexec
    set -l message "finished"
    if test $status -ne 0
      set message "errored"
    end
    # TODO linux SSH support
    # NEEDS TO BE BELOW THAT ABOVE CODE
    if test (uname) != Darwin
      return
    end
    set -l tty (osascript -e 'tell application "Terminal"
        if frontmost of window 1 then
          return tty of selected tab of window 1
        end if
      end tell')
    if test "$tty" != (tty)
      if test -f "/tmp/e-$TERM_SESSION_ID"
        rm "/tmp/e-$TERM_SESSION_ID"
      else
        if test $message = "errored"
          echo -en '\a'
        end
        set -l cmd (string split ' ' $argv)[1]
        set -l duration (math (date +%s) - $preexec_time)
        # TODO clicking on this should switch to the tab and window of completed command
        noti "$argv" "$duration"s "$cmd $message"
      end
    end
  end

  # TODO I don't like the way this stuff works.
  # it's a bad idea to store it in a universal variable
  # that is not globally shared across multiple computers
  set -U fish_greeting
  set -U fish_color_user 66233c
  set -U fish_color_host 875f5f
  set -U fish_color_cwd af005f
  set -U fish_color_search_match --background=ffff87
  set -U fish_pager_color_description 581D5B
  set -U fish_pager_color_prefix --bold black
  set -U fish_pager_color_progress brwhite --background=af005f

  set -gx EDITOR 'e'
  # set -gx MANPAGER 'nvim -c "set ft=man" -'
  set -gx PATH ~/.local/bin $PATH
  if test (hostname) = aubble
    set -gx PATH /snap/bin $PATH
  end

  set -gx GOPATH ~/Programming/gopath
  set -gx PATH $GOPATH/bin $PATH

  # TODO CAN I REMOVE THESE TWO?
  set -gx ERL_AFLAGS '-kernel shell_history enabled'
  set -gx NOGC 1

  # TODO set LS COLORS

  abbr -a gst git status
  abbr -a gsh git stash
  abbr -a ga git add
  abbr -a gc git commit
  abbr -a gcm git commit -m
  abbr -a gca git commit --amend
  abbr -a gch git checkout
  abbr -a gp git push
  abbr -a gd git diff
  abbr -a gl git log
  abbr -a gb git branch

  abbr -a mps mix phx.server
  abbr -a mdg mix deps.get
end
