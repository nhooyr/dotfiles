function wait_internet
	while not ping -c 1 -t 1 8.8.8.8
	end
end