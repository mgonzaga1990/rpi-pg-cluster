#!/bin/bash
 
set -e

PGHOST=${PRIMARY_NODE}

if [ -s $PGDATA/repmgr.conf ]; then
    return
fi

echo '~~ 02: repmgr conf' >&2

counter=0
limit=10
while [ $counter -lt $limit  ]
do
 server="pg-"$counter".pg-headless.default.svc.cluster.local"
 
 if ping -c 5 $server; then
  echo 'server up:' $server
  repmgr_installed=$(PGPASSWORD=repmgr psql -qAt -h "$server" -U repmgr repmgr -c "SELECT 1 FROM pg_tables WHERE tablename='nodes'")
  if [ "${repmgr_installed}" == "1"  ]; then
    echo 'repmgr found on : ' ${server}
    host=`(PGPASSWORD=repmgr psql -qAt -h $server -U repmgr -d repmgr -c "select substring(conninfo,6) from repmgr.nodes where type ='primary' and active='t'")`
    IFS=' ' read -r -a array <<< "$host"

    TMP_HOST="${array[0]}"
    if [ ! -z "$TMP_HOST" ]; then
      PGHOST=$TMP_HOST
      echo 'Primary host detected: ' ${PGHOST}
      break;
    fi
  fi
 else
   echo 'server down:' $server
 fi

 ((counter=counter+1))
done
until pg_isready --username=postgres --host=${PGHOST}; do echo "Waiting for Postgres..." && sleep 1; done

if ! [ -e ~/.pgpass ]; then
	echo "*:5432:*:$REPMGR_USER:$REPMGR_PASSWORD" > ~/.pgpass
	chmod go-rwx ~/.pgpass
fi

installed=$(psql -qAt -h "$PGHOST" -U "$REPMGR_USER" "$REPMGR_DB" -c "SELECT 1 FROM pg_tables WHERE tablename='nodes'")
my_node=1
 
if [ "${installed}" == "1" ]; then
    my_node=$(psql -qAt -h "$PGHOST" -U "$REPMGR_USER" "$REPMGR_DB" -c 'SELECT max(node_id)+1 FROM repmgr.nodes')
fi

# allow the user to specify the hostname/IP for this node
if [ -z "$NODE_HOST" ]; then
	NODE_HOST=$(hostname -f)
fi

HOSTNAME='postgres-'${my_node}
NET_IF=`netstat -rn | awk '/^0.0.0.0/ {thif=substr($0,74,10); print thif;} /^default.*UG/ {thif=substr($0,65,10); print thif;}'`
NET_IP=`ifconfig ${NET_IF} | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'` 

cat<<EOF > /home/postgres/repmgr.conf
	node_id=${my_node}
	node_name=${HOSTNAME}
	conninfo='host=${NET_IP} user=repmgr password=repmgr dbname=repmgr connect_timeout=20'
	data_directory='${PGDATA}'

	log_level=INFO
	log_facility=STDERR
	log_status_interval=300
	
	pg_bindir='/usr/lib/postgresql/10/bin'
	use_replication_slots=yes
	
	failover=automatic
	promote_command='repmgr standby promote'
	follow_command='repmgr standby follow -W'
	
	service_start_command='pg_ctl -D ${PGDATA} start'
	service_stop_command='pg_ctl -D ${PGDATA} stop -m fast'
	service_restart_command='pg_ctl -D ${PGDATA} restart -m fast'
	service_reload_command='pg_ctl -D ${PGDATA} reload'
EOF
