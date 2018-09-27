function github
	set -l branch (git rev-parse --abbrev-ref HEAD)
	if test $status != 0
		return
	end

	set -l url (hub pr list -f %U\n -h $branch)
	if test -z $url
		set url (hub browse -u)
	end
	python -mwebbrowser $url >/dev/null
end