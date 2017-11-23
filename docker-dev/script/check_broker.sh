#!/bin/bash
set -e

rabbitmq_host=${RABBITMQ_HOST:-localhost}

broker_up="0"
for i in $(seq 1 5); do
    ret=`curl -sS -u guest:guest -H 'Content-Type: application/json' http://${rabbitmq_host}:15672/api/aliveness-test/%2f` || true
    if [ "${ret}" == '{"status":"ok"}' ]; then
        broker_up="1"
        break
    else
        echo "broker not yet ready: ${ret}"
    fi
    sleep 1
done
if [ "${broker_up}" == '1' ]; then
    echo "broker is up and running"
else
    echo "broker did not start properly or management API has not been enabled"
fi
exec bash
