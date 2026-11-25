function ghg --description 'Upload files or clipboard text as a GitHub gist'
    set -l usage 'Usage: ghg [-p|--public] [FILE...]

Create a secret gist from FILEs, or from the clipboard when no files are given.
Use - as a filename to read from standard input instead of the clipboard.
Print the gist URL and copy it to the clipboard with pbc.

  -p, --public    Create a public gist.
  -h, --help      Show this help.

Examples:
  ghg                    Upload the clipboard as a secret gist.
  ghg -p                 Upload the clipboard as a public gist.
  ghg file.txt other.md  Upload multiple files.
  printf hello | ghg -   Upload standard input.'
    argparse --name "$(status current-function)" h/help p/public -- $argv; or return
    if set -q _flag_help
        printf '%s\n' "$usage"
        return 0
    end
    set -l flags
    set -q _flag_public; and set flags --public
    set -l url
    if set -q argv[1]
        set url "$(gh gist create $flags -- $argv)"; or return
    else
        set -l clipboard $(
            pbpaste | string collect --allow-empty --no-trim-newlines
            test "$pipestatus[1]" -eq 0
        ); or return
        set url "$(printf '%s' "$clipboard" | gh gist create $flags -- -)"; or return
    end
    printf '%s\n' "$url" | pbc
end
