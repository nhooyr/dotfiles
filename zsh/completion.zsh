ZSH_AUTOSUGGEST_USE_ASYNC=1
source ~zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
bindkey "^v" autosuggest-execute

RESET_LS_COLORS="rs=00:di=00:ln=00:mh=00:pi=00:so=00:do=00:bd=00:cd=00:or=00:mi=00:su=00:sg=00:ca=00:tw=00:ow=00:st=00:ex=00:*.tar=00:*.tgz=00:*.arc=00:*.arj=00:*.taz=00:*.lha=00:*.lz4=00:*.lzh=00:*.lzma=00:*.tlz=00:*.txz=00:*.tzo=00:*.t7z=00:*.zip=00:*.z=00:*.dz=00:*.gz=00:*.lrz=00:*.lz=00:*.lzo=00:*.xz=00:*.zst=00:*.tzst=00:*.bz2=00:*.bz=00:*.tbz=00:*.tbz2=00:*.tz=00:*.deb=00:*.rpm=00:*.jar=00:*.war=00:*.ear=00:*.sar=00:*.rar=00:*.alz=00:*.ace=00:*.zoo=00:*.cpio=00:*.7z=00:*.rz=00:*.cab=00:*.wim=00:*.swm=00:*.dwm=00:*.esd=00:*.jpg=00:*.jpeg=00:*.mjpg=00:*.mjpeg=00:*.gif=00:*.bmp=00:*.pbm=00:*.pgm=00:*.ppm=00:*.tga=00:*.xbm=00:*.xpm=00:*.tif=00:*.tiff=00:*.png=00:*.svg=00:*.svgz=00:*.mng=00:*.pcx=00:*.mov=00:*.mpg=00:*.mpeg=00:*.m2v=00:*.mkv=00:*.webm=00:*.ogm=00:*.mp4=00:*.m4v=00:*.mp4v=00:*.vob=00:*.qt=00:*.nuv=00:*.wmv=00:*.asf=00:*.rm=00:*.rmvb=00:*.flc=00:*.avi=00:*.fli=00:*.flv=00:*.gl=00:*.dl=00:*.xcf=00:*.xwd=00:*.yuv=00:*.cgm=00:*.emf=00:*.ogv=00:*.ogx=00:*.aac=00:*.au=00:*.flac=00:*.m4a=00:*.mid=00:*.midi=00:*.mka=00:*.mp3=00:*.mpc=00:*.ogg=00:*.ra=00:*.wav=00:*.oga=00:*.opus=00:*.spx=00:*.xspf=00:"
MY_LS_COLORS="di=00:ln=35:so=32:pi=32:ex=31;01"
export LS_COLORS="$RESET_LS_COLORS:$MY_LS_COLORS"

# Color 153 from https://jonasjacek.github.io/colors/.
# https://stackoverflow.com/a/62008734/4283659
zstyle ":completion:*:default" list-colors ${(s.:.)MY_LS_COLORS} "ma=48;5;153;1"
# Binds Shift + Tab reverse completion.
# https://stackoverflow.com/a/842370/4283659
bindkey "^[[Z" reverse-menu-complete

zstyle ":completion:*" list-dirs-first true
zstyle ":completion:*" group-name ""
# Worth confirming that this is indeed correctly set.
zstyle ":completion:*" matcher-list "" "+m:{[:lower:]}={[:upper:]}" "+r:|[._-]=** r:|=**" "+l:|=* r:|=*"
zstyle ":completion:*" menu select yes
zstyle ":completion:*" list-prompt %B%p%b
zstyle ":completion:*" select-prompt %B%p%b
zstyle ':completion:*' use-cache true

# Always reloads command list before completing.
# https://bbs.archlinux.org/viewtopic.php?id=175388
# http://www.zsh.org/mla/users/2006/msg00181.html
zstyle ":completion:*" rehash true

# Disables ~<USER> completion. Way too many normally.
# I only want to see my bookmarks.
zstyle ":completion:*" users

autoload -Uz compinit
# See https://github.com/zsh-users/zsh-completions/issues/433#issuecomment-346395881 for -i.
# Allows sharing compinit with root.
compinit -i
