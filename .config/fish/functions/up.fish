function up
	set -l count "$argv"
	if [ -z "$count" ]
		set count 1
	end
	cd ..(seq "$count" | string join '..' | string replace -ar '\d' '/')
end
