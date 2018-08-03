function delete_all_remote_tags
	for tag in (git tag -l)
		git push --delete origin $tag
	end
end
