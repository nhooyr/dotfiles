function fish_right_prompt
  if not git rev-parse --abbrev-ref HEAD > /dev/null 2>&1
    return
  end

  set -l color_branch af5fd7
  if who am i | grep -q '('
    set color_branch ff005f
  end

  if test $USER = root
    set color_branch af0000
    if who am i | grep -q '('
      set color_branch brmagenta
    end
  end

  set_color $color_branch
  git rev-parse --abbrev-ref HEAD
  set_color normal
end