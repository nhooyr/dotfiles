function ymp3 --description 'Download youtube URLs as mp3s'
	if test (count $argv) -eq 0
		set argv (pbpaste)
	end
	cd (mktemp -d)
  if youtube-dl --extract-audio --audio-format mp3 --default-search ytsearch $argv
    mv * "$HOME/Music/iTunes/iTunes Media/Automatically Add to iTunes.localized"
  end
	prevd
end
