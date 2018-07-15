function gll
	if test (count $argv) != 3
		echo "not enough or too many arguments" > /dev/stderr
		return
	end
	echo git log "-L$argv[1],$argv[2]:$argv[3]"
end