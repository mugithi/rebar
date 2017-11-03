#!/bin/bash
set -e

set_listen_addresses() {
    sedEscapedValue="$(echo "$1" | sed 's/[\/&]/\\&/g')"
    sed -ri "s/^#?(listen_addresses\s*=\s*)\S+/\1'$sedEscapedValue'/" "$PGDATA/postgresql.conf"
}

if [[ $1 != postgres ]]; then
    exec "$@"
fi

mkdir -p "$PGDATA"
chown -R postgres "$PGDATA"

chmod g+s /run/postgresql
chown -R postgres /run/postgresql

declare -a join
if grep -q consul /etc/hosts; then
    # If there is a consul host entry, join it.
    join=(--retry-join consul)
elif [[ $CONSUL_JOIN ]]; then
    # Otherwise, try $CONSUL_JOIN
    join=()
    for j in $CONSUL_JOIN; do
        join+=(--retry-join "$j")
    done
else
    # Finally, see if there is a consul running on our gateway and try to join it
    join=(--retry-join $(ip route show scope global |awk '/default/ {print $3}'))
fi
consul agent --config-dir /etc/consul.d --data-dir /data "${join[@]}" &
unset join
unset j

answer=""
# We need consul to converge on a leader.
# This can take a little time, so we ask for
# leader status.  The leader status returns
# nothing, a string that says no leader, or
# the leader IP:port pair.  The default port
# is 8300 for server communication.
count=0
while [[ $answer != *:8300* ]]; do
    if [ $((count % 60)) -eq 0 ] ; then
        echo "Waiting for consul leader: $answer"
    fi
    sleep 1
    answer=`curl http://localhost:8500/v1/status/leader`
    count=$((count+1))
done

# look specifically for PG_VERSION, as it is expected in the DB dir
# If it is there, don't bother going through the rest of the init rigamarole.
[[ -s $PGDATA/PG_VERSION ]] && exec gosu postgres "$@"

gosu postgres initdb

# check password first so we can output the warning before postgres
# messes it up
if [ "$POSTGRES_PASSWORD" ]; then
    pass="PASSWORD '$POSTGRES_PASSWORD'"
    authMethod=md5
else
    # The - option suppresses leading tabs but *not* spaces. :)
    cat >&2 <<-'EOWARN'
****************************************************
WARNING: No password has been set for the database.
         This will allow anyone with access to the
         Postgres port to access your database. In
         Docker's default configuration, this is
         effectively any other container on the same
         system.
         Use "-e POSTGRES_PASSWORD=password" to set
         it in "docker run".
****************************************************
EOWARN

    pass=
    authMethod=trust
fi

{ echo; echo "host all all 0.0.0.0/0 $authMethod"; } >> "$PGDATA/pg_hba.conf"

set_listen_addresses '' # we're going to start up postgres, but it's not ready for use yet (this is initialization), so don't listen to the outside world yet
if [[ -d /var/lib/postgresql/backup ]]; then
    for f in pg_hba.conf pg_ident.conf postgresql.auto.conf postgresql.conf postmaster.opts; do
        cp "/var/lib/postgresql/backup/$f" "$PGDATA/$f"
    done
    chown -R postgres "$PGDATA"
fi
gosu postgres "$@" &
pid="$!"
for i in {30..0}; do
    if echo 'SELECT 1' | psql --username postgres &> /dev/null; then
        break
    fi
    echo 'PostgreSQL init process in progress...'
    sleep 1
done
if [ "$i" = 0 ]; then
    echo >&2 'PostgreSQL init process failed'
    exit 1
fi

: ${POSTGRES_USER:=postgres}
: ${POSTGRES_DB:=$POSTGRES_USER}

if [ "$POSTGRES_DB" != 'postgres' ]; then
    psql --username postgres <<-EOSQL
CREATE DATABASE "$POSTGRES_DB" ;
EOSQL
    echo
fi

if [ "$POSTGRES_USER" = 'postgres' ]; then
    op='ALTER'
else
    op='CREATE'
fi

psql --username postgres <<-EOSQL
$op USER "$POSTGRES_USER" WITH SUPERUSER $pass ;
EOSQL
echo

echo
if [[ -d /var/lib/postgresql/backup ]]; then
    gunzip -c /var/lib/postgresql/backup/pg_dump.gz |psql --username postgres
    rm -rf /var/lib/postgresql/backup
else
    for f in /docker-entrypoint-initdb.d/*; do
        case "$f" in
            *.sh)  echo "$0: running $f"; . "$f" ;;
            *.sql) echo "$0: running $f"; psql --username postgres --dbname "$POSTGRES_DB" < "$f" && echo ;;
            *)     echo "$0: ignoring $f" ;;
        esac
        echo
    done
fi
if ! kill -s TERM "$pid" || ! wait "$pid"; then
    echo >&2 'PostgreSQL init process failed'
    exit 1
fi

set_listen_addresses '*'

echo
echo 'PostgreSQL init process complete; ready for start up.'
echo
exec gosu postgres "$@"
