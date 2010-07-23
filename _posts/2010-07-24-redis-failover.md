---
layout: post
title: Automated Redis Failover
---

When we released Beetle back in April, we already knew that the [Redis][redis] server,
which is the key component for deduplicating redundant messages, was a single point of
failure in our system. However, we also trusted it to run for a few months without
crashing, giving us enough time to develop a system for switching Redis servers
automatically. And we were already able to switch manually, by just shutting down the the
master server and promoting the slave to a master role. We made use of this mechanism to
upgrade our Redis servers without any effect on system availability.

We're now happy to announce a new release of beetle (0.2.1). This release adds the
possibility to configure the system so that it performs a deduplication store master
switch automatically, should the currently active Redis master become unavailable due to a
hardware or network failure. When the previous master server becomes available again, it
is automatically reconfigured as a slave of the new master. This effectively turns beetle
into a 24/7 messaging solution, which can be run without operator intervention (except for
replacing failed nodes, upgrading software components, or repairing a partitioned
network).

### Motivation

Because the deduplication store it is such a critical piece in our messaging
infrastructure, it is essential that a failure of this service is as unlikely as
possible. As our AMQP workers are working in a highly distributed manner, all accessing
the same Redis server, automatic failover to another deduplication server has to be very
defensive and ensure that every worker in the system will switch to the new server, or
none switches. If the new server isn't accepted by every worker, no switch should be
performed. This ensures that even in the case of a partitioned network it is impossible
that two different workers use two different Redis servers for message deduplication,
thereby avoiding data inconsistency in the deduplication store.

Note that this places our solution into the CA space of the [CAP theorem][cap].

### Feature Summary

* automatic switch in case of redis master failure (duh)
* tolerate single machine failures without problems
* switch doesn't cause inconsistent data on the redis servers
* switch is only performed if all worker machines agree
* opt-in, only use the redis failover solution if you need it

### How it works

On each machine which runs message processors for redundant messages (and therefore needs
access to the deduplication store), we store the currently configured redis master in a
non volatile memory location. Currently this is just a file on disk (the redis master
file), but this could be changed if we experience performance problems with this
approach. The Beetle client library uses the information stored in the file to connect to
the configured redis master and checks the modification time of this file for each redis
operation to reconfigure itself if a master switch has occurred. This is done in such a
way that no redis operation fails, provided the master switch happens within a
configurable time interval.

The contents of the file is maintained by a small daemon process (RCC - Redis
Configuration Client), which communicates with a master configuration process (RCS - Redis
Configuration Server), running on an arbitrary machine in the network. The RCS and the
RCCs communicate via non-redundant Beetle messages, so they don't need to know each others
addresses. However, since we only want to switch the redis master if all worker machines
are willing to do so, the RCS needs to know how many RCCs exist and the RCCs need to be
distinguishable. This is achieved by providing the RCS with a list of known RCC names
(they default to the hostname the RCCs are running on).

The Redis Configuration Server constantly checks the availability and configuration of the
currently configured Redis master server. If it detects that the Redis master is no longer
available, it selects one of the configured (and available) slaves to become the new Redis
master and initiates a master reconfiguration process.

The reconfiguration process is started by sending a "ping" message to see if all known
RCCs are still online. As soon as all RCCs have answered the ping message, the RCS sends
out an "invalidate" message, asking the RCCs to invalidate the current master. Upon
receipt of the "invalidate" message, the RCCs delete the contents of the redis master file
on the machine they're running on, which in turn will signal the workers running on that
machine that a redis master reconfiguration is in progress and that they should wait for
the result.

Immediately after the file contents has been cleared, the RCCs respond to the invalidate
message by sending an "invalidated" message back to the RCS. When all RCCs have responded,
the RCS knows for sure that it is safe to switch the Redis master. It then performs the
master switch by sending a "SLAVEOF no one" command to the selected slave and a
"reconfigure" message with the new Redis master to the RCCs, which then update the redis
master file their machines, enabling the messaging workers to proceed with any pending
redis operations.
master switch by turning the selected slave into a master and sending a
"reconfigure" message with the new Redis master to the RCCs, which then update their redis
master file, enabling the messaging workers to proceed with any pending redis operations.

If one of the above mentioned steps fail, the RCS proceeds by starting a new
reconfiguration round, sending out a system failure notification message using Beetle.
You can subscribe to these system failure notification messages with a custom worker,
e.g. to send out emails to your operators.

Additional information on the failover mechanism can be found in the
[ruby documentation][rdoc].

### Implementation Status

The new Beetle version has been running in production for a few weeks now. A lot of effort
has been put into testing the failover mechanism. We have built cucumber tests for various
failure scenarios and we also have C0 test coverage. Failover has been tested using normal
Redis server shutdowns and also by disabling network cards on the Redis master in our
production system.

So far the failover system has worked flawlessly and we are confident it will continue to
do so. We are very happy with it. If you have used Beetle to build your messaging system,
we strongly suggest you upgrade to the new version.

By the way, we would love to here from you if you're using Beetle in a production system.


[cap]: http://www.julianbrowne.com/article/viewer/brewers-cap-theorem
[redis]: http://code.google.com/p/redis/
[failover_doc]: /beetle/tree/master/REDIS_FAILOVER.rdoc
[rdoc]: /beetle/rdoc/index.html
