function bd
	set -l pwd (string split '/' (pwd))[-2..1]
	for i in (seq (count $pwd))
		if echo $pwd[$i] | rg $argv > /dev/null 2>&1
			cd ..(string join '..' (seq (count $pwd[1..$i])) | string replace -ra '\d' '/')
			return
		end
	end
end
