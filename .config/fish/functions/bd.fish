function bd
	set -l pwd (string split --no-empty '/' $PWD)
	# Reverse directories.
	set -l pwd $pwd[-1..1]
	# Skip current directory.
	set -l pwd $pwd[2..-1]
	for i in (seq (count $pwd))
		if echo $pwd[$i] | rg -q $argv
			up $i
			return
		end
	end
end
