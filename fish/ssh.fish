abbrali sshak ssh-add --apple-load-keychain
set -q TMPDIR; or set -gx TMPDIR "$(mktemp -d)"
if not test -f "$TMPDIR/__aqsnow_ssh_keychain_loaded"
    sshak -q; and touch "$TMPDIR/__aqsnow_ssh_keychain_loaded"
end
abbrali sshq ssh -O exit
abbrali sshu ssh -oControlPath=none
abbrali ssha ssh-add
function socks --wraps 'sshu -ND1080'
    set -l name "$(status current-function)"
    if not set -q argv[1]
        printf 'Usage: %s [ssh-options] host\n' "$name" >&2
        return 1
    end

    set -l service
    for family in IPv4 IPv6
        set -l service_id $(printf 'show State:/Network/Global/%s\n' "$family" | scutil | string match -rg '^\s*PrimaryService : (.+)$'); or continue
        set service $(printf 'show Setup:/Network/Service/%s\n' "$service_id[1]" | scutil | string match -rg '^\s*UserDefinedName : (.+)$'); and break
    end
    if not set -q service[1]
        printf '%s: could not find the active macOS network service\n' "$name" >&2
        return 1
    end

    sudo -v; or return
    aqsnow_ssh_forward "$name" -D localhost:1080 $argv | command sudo -n sh -c '
            set -eu
            service=$1

            IFS= read -r command

            cleanup() {
                trap "" HUP INT TERM
                networksetup -setsocksfirewallproxystate "$service" off
                printf "%s: proxy disabled on %s\n" "$0" "$service"
            }
            trap cleanup 0
            trap "exit 129" HUP
            trap "exit 130" INT
            trap "exit 143" TERM
            networksetup -setsocksfirewallproxy "$service" localhost 1080 off
            printf "%s\n" "$command"
            while IFS= read -r line; do :; done
        ' "$name" "$service[1]"
    set -l results $pipestatus
    test "$results[1]" -eq 0; or return "$results[1]"
    return "$results[2]"
end
abbrali fsshl fssh -L
abbrali fsshr fssh -R
function fssh --argument-names direction src_port dst_port
    set -l name "$(status current-function)"
    if not set -q argv[4]; or not contains -- "$direction" -L -R
        printf 'Usage: %s -L|-R SRC_PORT DST_PORT [ssh-options] host\n' "$name" >&2
        return 1
    end
    for port in "$src_port" "$dst_port"
        if not string match -qr '^[0-9]{1,5}$' -- "$port"; or test "$port" -lt 1; or test "$port" -gt 65535
            printf '%s: invalid port: %s\n' "$name" "$port" >&2
            return 1
        end
    end

    aqsnow_ssh_forward "$name" "$direction" "$src_port:localhost:$dst_port" $argv[4..]
end
function aqsnow_ssh_forward --argument-names name direction ports
    set -e argv[1..3]
    set -l directory "$(mktemp -d)"; or return
    set -l control "$directory/socket"
    set -l forward_command "$(string join ' ' -- sshu "-N$(string sub --start 2 -- "$direction")" $(string escape -- "$ports" $argv))"
    set -l setup '
        set -e
        ssh -S "$control" -O forward "$direction" "$ports" "$@"
        if [ "$direction" = -R ]; then
            port=${ports%%:*}
            ssh -nT -S "$control" -o ProxyCommand=false -o ClearAllForwardings=yes "$@" \
                "sh -c \"command -v nc >/dev/null || exit 127; until nc -z -w 1 localhost $port; do sleep 0.1; done\""
        fi
    '

    # Authenticate before starting the five-second forwarding deadline.
    # An external reader lets the sshu function stream output while it runs.
    sshu -MN -S "$control" -o ControlPersist=no -o ClearAllForwardings=yes \
        -o ConnectTimeout=5 -o ConnectionAttempts=1 \
        -o PermitLocalCommand=yes -o 'LocalCommand=printf "ssh-authenticated\n"' \
        $argv | control="$control" direction="$direction" ports="$ports" setup="$setup" \
        forward_command="$forward_command" host="$argv[-1]" command sh -c '
        cleanup() {
            trap "" HUP INT TERM
            ssh -S "$control" -O exit "$host" >/dev/null 2>&1 || :
            rm -rf "${control%/*}"
        }
        trap cleanup 0
        trap "exit 129" HUP
        trap "exit 130" INT
        trap "exit 143" TERM

        IFS= read -r ready || exit 1
        [ "$ready" = ssh-authenticated ] || exit 1
        timeout 5 sh -c "$setup" "$0" "$@"
        result=$?
        if [ "$result" -ne 0 ]; then
            [ "$result" -ne 124 ] || printf "%s: forwarding timed out after 5s\n" "$0" >&2
            exit "$result"
        fi
        printf "%s\n" "$forward_command"
        while IFS= read -r line; do :; done
    ' "$name" $argv
    set -l results $pipestatus
    test "$results[1]" -eq 0; or return "$results[1]"
    return "$results[2]"
end
