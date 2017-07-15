function lolsay --description 'Write out a random cow with a random quote with random colors'
	cowsay -f (ls  ~/.nix-profile/share/cows/ | cut -f 10 | shuf | head -n 1) (fortune -o) | lolcat $argv;
end
