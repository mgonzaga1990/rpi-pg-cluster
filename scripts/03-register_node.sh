#!/bin/bash
 
set -e

installed=$(psql -qAt -h "$PGHOST" -U "$REPMGR_USER" "$REPMGR_DB" -c "SELECT 1 FROM pg_tables WHERE tablename='nodes'")

if [ "${installed}" != "1" ]; then
    echo '~~ 03: registering as primary'
    repmgr primary register
fi

my_node=$(grep node_id /etc/repmgr.conf | cut -d= -f 2)
is_reg=$(psql -qAt -h "$PGHOST" -U "$REPMGR_USER" "$REPMGR_DB" -c "SELECT 1 FROM repmgr.nodes WHERE node_id=${my_node}")
 
if [ "${is_reg}" != "1" ] && [ ${my_node} -gt 1 ]; then
    echo '~~ 03: registering as standby' 
    pg_ctl stop -D $PGDATA -m fast
    rm -Rf $PGDATA/*

    repmgr -h "$PGHOST" -U "$REPMGR_USER" -d "$REPMGR_DB" standby clone --fast-checkpoint
    cp /etc/postgresql/postgresql.conf /var/lib/postgresql/data/
 
    repmgr -h "$PGHOST" -U "$REPMGR_USER" -d "$REPMGR_DB" standby register --force
    
    pg_ctl start -D $PGDATA	
fi
