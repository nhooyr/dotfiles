export GOPATH=~gopath
prepend_PATH ~gopath/bin
prepend_PATH ~/.cargo/bin

prepend_PATH ~dotfiles/bin
if [ "$NVIM" -a "$NVIM_SESSION" ]; then
  export EDITOR=nvim_terminal_editor
  export MANPAGER="nvim +Man!"
elif command_exists mate; then
  export EDITOR="nvim"
elif command_exists nvim; then
  export EDITOR=nvim
  export MANPAGER="nvim +Man!"
elif command_exists vim; then
  export EDITOR=vim
elif command_exists vi; then
  export EDITOR=vi
elif command_exists nano; then
  export EDITOR=nano
fi
export MANWIDTH=80

prepend_PATH /usr/local/bin
# prepend_PATH ~/.local/bin

RESET_LS_COLORS="rs=00:di=00:ln=00:mh=00:pi=00:so=00:do=00:bd=00:cd=00:or=00:mi=00:su=00:sg=00:ca=00:tw=00:ow=00:st=00:ex=00:*.tar=00:*.tgz=00:*.arc=00:*.arj=00:*.taz=00:*.lha=00:*.lz4=00:*.lzh=00:*.lzma=00:*.tlz=00:*.txz=00:*.tzo=00:*.t7z=00:*.zip=00:*.z=00:*.dz=00:*.gz=00:*.lrz=00:*.lz=00:*.lzo=00:*.xz=00:*.zst=00:*.tzst=00:*.bz2=00:*.bz=00:*.tbz=00:*.tbz2=00:*.tz=00:*.deb=00:*.rpm=00:*.jar=00:*.war=00:*.ear=00:*.sar=00:*.rar=00:*.alz=00:*.ace=00:*.zoo=00:*.cpio=00:*.7z=00:*.rz=00:*.cab=00:*.wim=00:*.swm=00:*.dwm=00:*.esd=00:*.jpg=00:*.jpeg=00:*.mjpg=00:*.mjpeg=00:*.gif=00:*.bmp=00:*.pbm=00:*.pgm=00:*.ppm=00:*.tga=00:*.xbm=00:*.xpm=00:*.tif=00:*.tiff=00:*.png=00:*.svg=00:*.svgz=00:*.mng=00:*.pcx=00:*.mov=00:*.mpg=00:*.mpeg=00:*.m2v=00:*.mkv=00:*.webm=00:*.ogm=00:*.mp4=00:*.m4v=00:*.mp4v=00:*.vob=00:*.qt=00:*.nuv=00:*.wmv=00:*.asf=00:*.rm=00:*.rmvb=00:*.flc=00:*.avi=00:*.fli=00:*.flv=00:*.gl=00:*.dl=00:*.xcf=00:*.xwd=00:*.yuv=00:*.cgm=00:*.emf=00:*.ogv=00:*.ogx=00:*.aac=00:*.au=00:*.flac=00:*.m4a=00:*.mid=00:*.midi=00:*.mka=00:*.mp3=00:*.mpc=00:*.ogg=00:*.ra=00:*.wav=00:*.oga=00:*.opus=00:*.spx=00:*.xspf=00:"
NHOOYR_LS_COLORS="di=38;5;18:ln=35:so=32:pi=32:ex=31;01"
export LS_COLORS="$RESET_LS_COLORS:$NHOOYR_LS_COLORS"

export HUSKY_SKIP_HOOKS=1

export XDG_DATA_HOME=~/.local/share
export PLAN9=$HOME/src/9fans/plan9port
export PATH=$PATH:$PLAN9/bin
