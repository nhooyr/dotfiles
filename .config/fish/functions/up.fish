function up
	set -l count "$argv"
	if [ -z "$count" ]
		set count 1
	end
	cd (string join .. (string repeat -n $count ' /' | string split ' '))
end
