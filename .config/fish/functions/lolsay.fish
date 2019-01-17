function lolsay
    cowsay -f (ls  /usr/local/share/cows | cut -f 10 | shuf | head -n 1) (fortune -o) | lolcat $argv
end
