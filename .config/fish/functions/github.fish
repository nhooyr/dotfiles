function github
	set -l url
	set -l branch (git rev-parse --abbrev-ref HEAD)
	if test $status -eq 0
		set url (hub pr list -f %U\n -h $branch)
	end

	if test -z $url
		set url (hub browse -u)
	end

	python -mwebbrowser $url >/dev/null
end