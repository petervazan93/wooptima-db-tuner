dbtune_test_close_non_std_fds() {
    local fd line pid tmpfile
    local -a open_fds=()

    pid=$BASHPID
    tmpfile=$(mktemp "$BATS_TEST_TMPDIR/open-fds.XXXXXX") || return 1

    if [[ -d /proc/$pid/fd ]]; then
        command ls -1 "/proc/$pid/fd" >"$tmpfile" || {
            rm -f "$tmpfile"
            return 1
        }
    elif command -v lsof >/dev/null 2>&1; then
        command lsof -F f -p "$pid" >"$tmpfile" || {
            rm -f "$tmpfile"
            return 1
        }
    else
        rm -f "$tmpfile"
        return 69
    fi

    while IFS= read -r line; do
        case $line in
            f[0-9]*) fd=${line#f} ;;
            [0-9]*) fd=$line ;;
            *) continue ;;
        esac
        case $fd in
            ''|*[!0-9]*) continue ;;
        esac
        if ((fd >= 3 && fd <= 254)); then
            open_fds+=("$fd")
        fi
    done <"$tmpfile"
    rm -f "$tmpfile"

    for fd in "${open_fds[@]}"; do
        eval "exec ${fd}>&-"
    done
}
