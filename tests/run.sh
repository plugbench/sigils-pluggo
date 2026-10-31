#!/usr/bin/env bash
# Tests `sigils`, built with the fake backend, given as $1, against a
# nats-server of its own.

set -u

sigils=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
failures=0
tests=0

nats_dir=$(mktemp -d "${TMPDIR:-/tmp}/sigils-nats.XXXXXX")
nats_port=$((20000 + RANDOM % 20000))
export NATS_URL=nats://127.0.0.1:$nats_port NATS_TOKEN=s3cret
nats-server -a 127.0.0.1 -p "$nats_port" --auth "$NATS_TOKEN" >"$nats_dir/log" 2>&1 &
nats_pid=$!
disown
trap 'kill "$nats_pid" 2>/dev/null; rm -rf "$nats_dir"' EXIT
until grep -q 'Server is ready' "$nats_dir/log"; do
    kill -0 "$nats_pid" 2>/dev/null || { cat "$nats_dir/log"; exit 1; }
    sleep 0.01
done

setup() {
    dir=$(mktemp -d "${TMPDIR:-/tmp}/sigils.XXXXXX")
    export SIGILS_LOCK=$dir/sigils.lock
    export SIGILS_FAKE_WINDOWS=$dir/windows
    cat >"$SIGILS_FAKE_WINDOWS" <<'WINDOWS'
display 0 0 1000 800
window 11 0 0 500 800 org.example.editor notes.txt
window 12 501 0 499 400 org.example.browser A Page
WINDOWS
}

start_daemon() {
    "$sigils" --daemon "$@" &
    local pid=$!
    disown
    while [[ $(daemon_pid) != "$pid" ]]; do sleep 0.01; done
}

daemon_pid() {
    head -1 "$SIGILS_LOCK" 2>/dev/null
}

teardown() {
    local pid
    pid=$(daemon_pid)
    [[ -n $pid ]] && kill "$pid" 2>/dev/null
    rm -rf "$dir"
}

fail() {
    printf 'FAIL: %s\n  %s\n' "$name" "$1"
    failures=$((failures + 1))
}

expect_eq() {
    [[ $1 == "$2" ]] || fail "expected [$2], got [$1]"
}

run_test() {
    name=$1
    tests=$((tests + 1))
    setup
    "$1"
    teardown
}

lists_windows_and_empty_spaces_in_position_order() {
    expect_eq "$("$sigils")" "a 11 0 0 500 800 org.example.editor notes.txt
b 12 501 0 499 400 org.example.browser A Page
c 0 501 401 499 399 - "
}

looks_up_the_window_id_of_one_sigil() {
    expect_eq "$("$sigils" b)" 12
}

looks_up_zero_for_an_empty_space() {
    expect_eq "$("$sigils" c)" 0
}

fails_for_a_sigil_no_window_has() {
    local err status
    err=$("$sigils" z 2>&1 >/dev/null)
    status=$?
    expect_eq "$status" 1
    expect_eq "$err" "sigils: no window has the sigil z"
}

hands_out_the_characters_given_to_the_daemon_with_s() {
    start_daemon -s xy
    expect_eq "$("$sigils" | cut -d' ' -f1,2)" "x 11
y 12"
}

keeps_edges_given_to_the_daemon_with_i_out_of_empty_spaces() {
    start_daemon -i bottom=100
    expect_eq "$("$sigils" | grep '^c ')" "c 0 501 401 499 298 - "
}

rejects_malformed_insets() {
    local err status
    err=$("$sigils" --daemon -i middle=4 2>&1)
    status=$?
    expect_eq "$status" 2
    expect_eq "$err" "sigils: bad insets middle=4"
}

rejects_s_and_i_for_queries() {
    local err status
    err=$("$sigils" -s xy 2>&1)
    status=$?
    expect_eq "$status" 2
    expect_eq "$err" "sigils: -s and -i are only for --daemon"
    [[ -s $SIGILS_LOCK ]] && fail "a daemon was started"
}

leaves_out_empty_spaces_smaller_than_twenty_pixels() {
    echo "window 13 501 401 499 380 org.example.term shell" >>"$SIGILS_FAKE_WINDOWS"
    expect_eq "$("$sigils" | cut -d' ' -f2)" "11
12
13"
}

gives_no_sigils_to_bars_and_decorations_or_the_space_they_cover() {
    echo "chrome 501 401 499 399" >>"$SIGILS_FAKE_WINDOWS"
    expect_eq "$("$sigils" | cut -d' ' -f2)" "11
12"
}

starts_a_daemon_when_none_is_running() {
    "$sigils" >/dev/null
    kill -0 "$(daemon_pid)" 2>/dev/null || fail "no daemon running"
}

reuses_a_running_daemon() {
    "$sigils" >/dev/null
    local first
    first=$(daemon_pid)
    "$sigils" a >/dev/null
    expect_eq "$(daemon_pid)" "$first"
}

sees_windows_change_between_queries() {
    "$sigils" >/dev/null
    echo "window 13 501 401 499 399 org.example.term shell" >>"$SIGILS_FAKE_WINDOWS"
    expect_eq "$("$sigils" c)" 13
}

replaces_a_daemon_which_died() {
    "$sigils" >/dev/null
    local first
    first=$(daemon_pid)
    kill -9 "$first"
    while kill -0 "$first" 2>/dev/null; do sleep 0.01; done
    expect_eq "$("$sigils" a)" 11
    [[ $(daemon_pid) != "$first" ]] || fail "the dead daemon's pid is still in the lock"
}

answers_simultaneous_queries_with_one_daemon() {
    local i outputs=$dir/outputs
    for i in 1 2 3 4 5 6 7 8; do
        "$sigils" a >"$outputs.$i" &
    done
    wait
    for i in 1 2 3 4 5 6 7 8; do
        expect_eq "$(cat "$outputs.$i")" 11
    done
    kill -0 "$(daemon_pid)" 2>/dev/null || fail "no daemon holds the lock"
}

restarts_a_daemon_which_died_with_its_s_and_i() {
    start_daemon -s xy -i bottom=100
    local first
    first=$(daemon_pid)
    kill -9 "$first"
    while kill -0 "$first" 2>/dev/null; do sleep 0.01; done
    expect_eq "$("$sigils" | cut -d' ' -f1,6)" "x 800
y 400"
}

replaces_a_running_daemon() {
    start_daemon -s xy
    local first
    first=$(daemon_pid)
    "$sigils" --daemon -s pq &
    while [[ $(daemon_pid) == "$first" ]]; do sleep 0.01; done
    kill -0 "$first" 2>/dev/null && fail "the first daemon is still running"
    expect_eq "$("$sigils" | cut -d' ' -f1 | head -1)" p
}


# On macOS, the default is the user's real temporary directory, which a test
# can't have to itself.
puts_the_lock_in_xdg_runtime_dir_by_default_off_macos() {
    [[ $(uname) == Darwin ]] && return
    unset SIGILS_LOCK
    XDG_RUNTIME_DIR=$dir "$sigils" >/dev/null
    [[ -s $dir/sigils.lock ]] || fail "no lock at $dir/sigils.lock"
    SIGILS_LOCK=$dir/sigils.lock
}

fails_when_nats_cant_be_reached() {
    local err status
    err=$(NATS_URL=nats://127.0.0.1:1 "$sigils" a 2>&1)
    status=$?
    expect_eq "$status" 1
    [[ $err == "sigils: can't reach NATS at 127.0.0.1:1: "* ]] || fail "expected can't reach, got [$err]"
}

fails_with_the_wrong_token() {
    local err status
    err=$(NATS_TOKEN=wrong "$sigils" a 2>&1)
    status=$?
    expect_eq "$status" 1
    [[ $err == *"Authorization Violation"* ]] || fail "expected an authorization violation, got [$err]"
}

prints_usage_for_an_unknown_option() {
    local err status
    err=$("$sigils" -x 2>&1)
    status=$?
    expect_eq "$status" 2
    [[ $err == usage:* ]] || fail "expected usage, got [$err]"
}

for t in $(declare -F | awk '{print $3}' | grep -v -e '^setup$' -e '^teardown$' \
        -e '^daemon_pid$' -e '^start_daemon$' -e '^fail$' -e '^expect_eq$' -e '^run_test$'); do
    run_test "$t"
done

printf '%d tests, %d failures\n' "$tests" "$failures"
[[ $failures -eq 0 ]]
