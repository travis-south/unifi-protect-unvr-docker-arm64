#!/usr/bin/env bash

set -euo pipefail

image="${1:?Usage: $0 IMAGE}"

docker run --rm -i --entrypoint bash "$image" -s <<'CONTAINER'
set -euo pipefail

zoneinfo=/usr/share/zoneinfo/Etc/UTC
pgdata=/tmp/postgresql-timezone-check
pglog=/tmp/postgresql-timezone-check.log
port=55432

if [[ ! -r "$zoneinfo" ]]; then
    echo "Diagnostic: $zoneinfo is missing or unreadable" >&2
fi

install -d -m 0700 -o postgres -g postgres "$pgdata"
runuser -u postgres -- /usr/lib/postgresql/14/bin/initdb \
    -D "$pgdata" --no-locale --auth=trust >/dev/null
printf "\nlog_timezone = 'Etc/UTC'\ntimezone = 'Etc/UTC'\n" \
    >> "$pgdata/postgresql.conf"

cleanup() {
    if [[ -s "$pgdata/postmaster.pid" ]]; then
        runuser -u postgres -- /usr/lib/postgresql/14/bin/pg_ctl \
            -D "$pgdata" -m immediate -w stop >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

if ! runuser -u postgres -- /usr/lib/postgresql/14/bin/pg_ctl \
    -D "$pgdata" \
    -l "$pglog" \
    -o "-c listen_addresses=127.0.0.1 -c port=$port -c unix_socket_directories=/tmp" \
    -t 10 -w start; then
    cat "$pglog" >&2
    if grep -Fq 'invalid value for parameter "log_timezone": "Etc/UTC"' "$pglog" \
        && grep -Fq 'invalid value for parameter "TimeZone": "Etc/UTC"' "$pglog"; then
        echo "RED: PostgreSQL rejected Etc/UTC" >&2
    fi
    exit 1
fi

test "$(runuser -u postgres -- psql -h /tmp -p "$port" -Atqc 'show log_timezone')" = "Etc/UTC"
test "$(runuser -u postgres -- psql -h /tmp -p "$port" -Atqc 'show timezone')" = "Etc/UTC"

echo "GREEN: PostgreSQL accepts Etc/UTC"
CONTAINER
