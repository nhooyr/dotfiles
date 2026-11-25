function papp --wraps 'git apply' --description 'git apply from clipboard'
    pbpaste | perl -pe 's/\n?\z/\n/' | git apply $argv
end
