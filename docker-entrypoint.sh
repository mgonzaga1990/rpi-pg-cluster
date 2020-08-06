#!/bin/bash

# Backwards compatibility for old variable names (deprecated)
if [ "x$PGUSER"     != "x" ]; then
    POSTGRES_USER=$PGUSER
fi
if [ "x$PGPASSWORD" != "x" ]; then
    POSTGRES_PASSWORD=$PGPASSWORD
fi

# Forwards-compatibility for old variable names (pg_basebackup uses them)
if [ "x$PGPASSWORD" = "x" ]; then
    export PGPASSWORD=$POSTGRES_PASSWORD
fi

echo "Validating Master Host"
MASTER_HOST=$(nslookup pg-master-0.pg-master-headless | awk 'FNR == 5 {print $2}')

# Based on official postgres package's entrypoint script (https://hub.docker.com/_/postgres/)
# Modified to be able to set up a slave. The docker-entrypoint-initdb.d hook provided is inadequate.

set -e

if [ "${1:0:1}" = '-' ]; then
	set -- postgres "$@"
fi

if [ "$1" = 'postgres' ]; then
	mkdir -p "$PGDATA"
	chmod 700 "$PGDATA"
	chown -R postgres "$PGDATA"

	mkdir -p /run/postgresql
	chmod g+s /run/postgresql
	chown -R postgres /run/postgresql

	# look specifically for PG_VERSION, as it is expected in the DB dir
	if [ ! -s "$PGDATA/PG_VERSION" ]; then
	    if [ "x$MASTER_HOST" == "x" ]; then
                echo "No Master Host Found"
		eval "gosu postgres initdb $POSTGRES_INITDB_ARGS"
	    else
                echo "Master host found : " ${MASTER_HOST}
            	until ping -c 1 -W 1 ${MASTER_HOST}
            	do
                	echo "Waiting for master to ping..."
                	sleep 1s
            	done
            	until gosu postgres pg_basebackup -h ${MASTER_HOST} -p 5432 -D ${PGDATA} -U postgres -w 
            	do
                	echo "Waiting for master to connect..."
                	sleep 1s
            	done
                
                #WAL (Write Ahead Log) setting
   		echo "setting wal_level to host_standby"
   		sed -i "s/#wal_level = minimal/wal_level = hot_standby/g"  ${PGDATA}/postgresql.conf

   		#wal sender process
   		echo "setting max_wal_senders to 3"
  		sed -i "s/#max_wal_senders = 0/max_wal_senders = 20/g"  ${PGDATA}/postgresql.conf
  		 
		echo "setting wal_keep_segments to 8"
  		sed -i "s/#wal_keep_segments = 0/wal_keep_segments = 10/g"  ${PGDATA}/postgresql.conf

               	#recovery file
              	#Set to hot standby
 		echo "setting hot_standby to on"
 		sed -i "s/#hot_standby = off/ hot_standby = on/g"  ${PGDATA}/postgresql.conf

 		echo "Creating recovery.conf file in ${PGDATA}"
 		RECOVERY_PATH=${PGDATA}/recovery.conf
 		cat >> ${RECOVERY_PATH}
 		echo "standby_mode = 'on'" >> ${RECOVERY_PATH}
 		echo "primary_conninfo = 'host=${MASTER_HOST} port=5432 user=${POSTGRES_USER} password=${POSTGRES_PASSWORD}'" >> ${RECOVERY_PATH}
 		echo "restore_command = 'cp ${PGDATA}/archive/%f %p'" >> ${RECOVERY_PATH}
		echo "trigger_file = '/tmp/postgresql.trigger.5432'" >> ${RECOVERY_PATH}
 		chmod +rwx ${RECOVERY_PATH}

	    fi

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

		if [ "x$MASTER_HOST" == "x" ]; then

		{ echo; echo "host replication all 0.0.0.0/0 trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null
		{ echo; echo "host all all 0.0.0.0/0 trust"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf" > /dev/null

		# internal start of server in order to allow set-up using psql-client		
		# does not listen on external TCP/IP and waits until start finishes
		gosu postgres pg_ctl -D "$PGDATA" \
			-o "-c listen_addresses='localhost'" \
			-w start

		: ${POSTGRES_USER:=postgres}
		: ${POSTGRES_DB:=$POSTGRES_USER}
		export POSTGRES_USER POSTGRES_DB

		psql=( psql -v ON_ERROR_STOP=1 )

		if [ "$POSTGRES_DB" != 'postgres' ]; then
			"${psql[@]}" --username postgres <<-EOSQL
				CREATE DATABASE "$POSTGRES_DB" ;
			EOSQL
			echo
		fi

		if [ "$POSTGRES_USER" = 'postgres' ]; then
			op='ALTER'
		else
			op='CREATE'
		fi
		"${psql[@]}" --username postgres <<-EOSQL
			$op USER "$POSTGRES_USER" WITH SUPERUSER $pass ;
		EOSQL
		echo
		
		fi

		psql+=( --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" )

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)     echo "$0: running $f"; . "$f" ;;
				*.sql)    echo "$0: running $f"; "${psql[@]}" < "$f"; echo ;;
				*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${psql[@]}"; echo ;;
				*)        echo "$0: ignoring $f" ;;
			esac
			echo
		done

	if [ "x$MASTER_HOST" == "x" ]; then
		gosu postgres pg_ctl -D "$PGDATA" -m fast -w stop
	fi

		echo
		echo 'PostgreSQL init process complete; ready for start up.'
		echo
	fi

	exec gosu postgres "$@"
fi

exec "$@"
