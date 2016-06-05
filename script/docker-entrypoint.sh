#!/bin/bash
set -e
/etc/init.d/mysql start
/etc/init.d/rabbitmq-server start
redis-server etc/redis-master.conf --daemonize yes
redis-server etc/redis-slave.conf --daemonize yes
exec "$@"
