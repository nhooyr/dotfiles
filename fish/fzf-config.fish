set -gx FZF_DEFAULT_OPTS "--style=minimal --layout=reverse --height=~50% --min-height=0 --cycle \
    --bind=ctrl-/:toggle-preview --bind=ctrl-s:toggle-sort --no-mouse --scroll-off=0 --info=inline-right \
    --color=bw,query:regular,info:italic,hl:underline,fg+:regular:reverse,\
hl+:reverse:underline,pointer:magenta:bold"
# Display no prefix by default in history view.
set -gx FZF_CTRL_R_OPTS "--with-nth 3.. --bind 'alt-t:change-with-nth(2..|1,3..|3..)'"
function aqsnow_fzf_diralis_add
    for name in $argv
        contains -- "$name" $aqsnow_fzf_diralis; or set -ga aqsnow_fzf_diralis "$name"
    end
end
aqsnow_fzf_diralis_add HOME nhooyr dotfiles notes noise

for mode in default insert
    bind -M "$mode" ctrl-r 'fzf_accept_and_run fzf-history-widget'
    bind -M "$mode" ctrl-t 'fzf_accept_and_run fzf-file-widget'
    bind -M "$mode" alt-v 'fzf_accept_and_run fzf-path-widget'
    bind -M "$mode" alt-c 'fzf_accept_and_run fzf-cd-widget'
    bind -M "$mode" shift-tab 'fzf_accept_and_run fzf_complete'
end

# Editors launched by commands need to inherit the handoff path.
function aqsnow_init_rendezvous --on-event fish_preexec
    set -q __aqsnow_rendezvous_dir; and return
    set -e AQSNOW_FISH_RENDEZVOUS
    set -l rendezvous_dir "$(mktemp -d)"; or return
    set -g __aqsnow_rendezvous_dir "$rendezvous_dir"
    set -gx AQSNOW_FISH_RENDEZVOUS "$rendezvous_dir/rendezvous"
    function aqsnow_rm_rendezvous --on-event fish_exit --inherit-variable rendezvous_dir
        rm -rf -- "$rendezvous_dir"
    end
end
function aqsnow_run_requested
    test -s "$AQSNOW_FISH_RENDEZVOUS"; or return 1
    if not printf '%s\n' '<M-v>' | cmp -s - "$AQSNOW_FISH_RENDEZVOUS"
        rm -- "$AQSNOW_FISH_RENDEZVOUS"
        return 0
    end
    rm -- "$AQSNOW_FISH_RENDEZVOUS"
    fzf_accept_and_run fzf-path-widget
    return 1
end
function aqsnow_rendezvous
    aqsnow_run_requested; or return 0
    aqsnow_exec
    set -g fish_bind_mode insert
end
