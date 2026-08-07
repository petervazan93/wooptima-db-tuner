dbtune_test_close_non_std_fds() {
    local fd

    # Bash may reserve descriptor 255 for script input.
    for ((fd = 3; fd <= 254; fd++)); do
        eval "exec ${fd}>&-"
    done
}
