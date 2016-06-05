#!/bin/bash
set -e
/etc/init.d/mysql start
redis-server etc/redis-master.conf --daemonize yes
redis-server etc/redis-slave.conf --daemonize yes
/etc/init.d/rabbitmq-server start
broker_up=0
for i in 1..15; do
    ret=`curl -s -u guest:guest -H 'Content-Type: application/json' http://localhost:15674/api/aliveness-test/%2f`
    [ $ret == '{"status":"ok"}' ] && broker_up=1 && break
    sleep 1
done
if [ $broker_up == '1' ]; then
   echo "broker is up and running"
else
    echo "broker did not start properly or management API has not been enabled"
    exit 1
fi
exec "$@"
