function gcd
	set -l gcd (git rev-parse --show-toplevel)
	if [ "$status" -eq 0 ]
		cd "$gcd"
	end
end
