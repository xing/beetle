#!/bin/bash
set -e
/etc/init.d/mysql start
redis-server etc/redis-master.conf --daemonize yes
redis-server etc/redis-slave.conf --daemonize yes
rake rabbit:start1&
sleep 5
ps auxww
lsof | grep LISTEN
exec "$@"
