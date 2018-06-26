# Defined in - @ line 0
function delete_all_remote_tags --description 'alias delete_all_remote_tags=git tag -l | xargs -n 1 echo git push --delete origin'
	git tag -l | xargs -n 1 -P 32 git push --delete origin
end
