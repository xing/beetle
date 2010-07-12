---
layout: post
title: Automated Redis Failover
---

When we released Beetle back in April, we already knew that the Redis server, which is the
key component for message deduplication, was a single point of failure in our
system. However, we also trusted it to run for a few months without crashing, giving us
enough time to develop a system for switching Redis servers automatically. And we were
already able to switch manually, by just shutting down the the master server and
restarting the slave as a master. We made use of this mechanism to upgrade our redis
servers without losing a single message.

### Motivation

Redis is used as the persistence layer in the AMQP message deduplication process. Because
it is such a critical piece in our infrastructure, it is essential that a failure of this
service is as unlikely as possible. As our AMQP workers are working in a highly
distributed manner, all accessing the same Redis server, automatic failover to another
Redis server has to be very defensive and ensure that every worker in the system will
switch to the new server at the same time. If the new server would not get accepted from
every worker, a switch would not be possible. This ensures that even in the case of a
partitioned network it is impossible that two different workers use two different Redis
servers for message deduplication.

### Our goals

* opt-in, no need to use the redis-failover solution
* no single point of failure
* automatic switch in case of redis-master failure
* switch should not cause inconsistent data on the redis servers
* workers should be able to determine the current redis-master without asking
  another process (as long as the redis servers are working)

### How it works

To ensure consistency, a service (the Redis Configuration Server - RCS) is constantly
checking the availability and configuration of the currently configured Redis master
server. If this service detects that the Redis master is no longer available, it tries to
find an alternative server (one of the slaves) which could be promoted to be the new Redis
master.

On every worker server runs another daemon, the Redis Configuration Client (RCC) which
listens to messages sent by the RCS.

If the RCS finds another potential Redis Master, it sends out a message to see if all
known RCCs are still available (once again to eliminate the risk of a partitioned network)
and if they agree to the master switch.

If all RCCs have answered to that message, the RCS sends out a message which tells the
RCCs to invalidate the current master.

This happens by deleting the contents of a special file which is used by the workers to
store the current Redis master (the content of that file is the hostname:port of the
currently active Redis master). By doing that, it is ensured that no operations are done
to the old Redis master server anymore, because the AMQP workers check this file's mtime
and reads its contents in case that the file changed, before every Redis operation. When
the file has been emptied, the RCCs respond to the "invalidate" message of the RCS. When
all RCCs have responded, the RCS knows for sure that it is safe to switch the Redis master
now. It sends a "reconfigure" message with the new Redis master hostname:port to the RCCs,
which then write that value into their redis master file.

Additionally, the RCS sends reconfigure messages with the current Redis master
periodically, to allow new RCCs to pick up the current master. Plus it turns
all other redis servers into slaves of the current master.

### What this means

Well, this means that we now have a 24/7 messaging bus, which can tolerate single machine
failures, regardless of which kind of machine it is.

