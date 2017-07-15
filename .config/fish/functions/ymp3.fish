function ymp3 --description 'Download youtube URLs as mp3s'
	if test (count $argv) -eq 0
		set argv (pbpaste)
	end
	cd ~/Music/Downloads
	youtube-dl --extract-audio --audio-format mp3 --default-search ytsearch $argv
	prevd
end
