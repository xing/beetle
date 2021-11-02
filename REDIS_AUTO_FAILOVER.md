# Automatic Redis Failover for Beetle

## Introduction

Redis is used as the persistence layer in the AMQP message deduplication
process. Because it is such a critical piece in our infrastructure, it is
essential that a failure of this service is as unlikely as possible. As our
AMQP workers are working in a highly distributed manner, all accessing the same
Redis server, a automatic failover to another Redis server has to be very
defensive and ensure that every worker in the system will switch to the new
server at the same time. If the new server would not get accepted from every
worker, a switch would not be possible. This ensures that even in the case of a
partitioned network it is impossible that two different workers use two
different Redis servers for message deduplication.

## Our goals

* opt-in, no need to use the redis-failover solution
* no single point of failure
* automatic switch in case of redis-master failure
* switch should not cause inconsistent data on the redis servers
* workers should be able to determine the current redis-master without asking
  another process (as long as the redis servers are working)

## How it works

To ensure consistency, a service (the Redis Configuration Server - RCS) is
constantly checking the availability and configuration of the currently
configured Redis master server. If this service detects that the Redis master
is no longer available, it tries to find an alternative server (one of the
slaves) which could be promoted to be the new Redis master.

On every worker server runs another daemon, the Redis Configuration Client
(RCC) which listens to messages sent by the RCS.

If the RCS finds another potential Redis Master, it sends out a message to see
if all known RCCs are still available (once again to eliminate the risk of a
partitioned network) and if they agree to the master switch.

If all RCCs have answered to that message, the RCS sends out a message which
tells the RCCs to invalidate the current master.

This happens by deleting the contents of a special file which is used
by the workers to store the current Redis master (the content of that file is
the hostname:port of the currently active Redis master). By doing that, it is
ensured that no operations are done to the old Redis master server anymore, because the
AMQP workers check this file's mtime and reads its contents in case that the
file changed, before every Redis operation. When the file has been emptied, the
RCCs respond to the "invalidate" message of the RCS. When all RCCs have
responded, the RCS knows for sure that it is safe to switch the Redis master
now. It sends a "reconfigure" message with the new Redis master hostname:port
to the RCCs, which then write that value into their redis master file.

Additionally, the RCS sends reconfigure messages with the current Redis master
periodically, to allow new RCCs to pick up the current master. Plus it turns
all other redis servers into slaves of the current master.

### Prerequisites

* one redis-configuration-server process ("RCS", on one server), one redis-configuration-client process ("RCC") on every worker server
* the RCS knows about all possible RCCs using a list of client ids
* the RCS and RCCs exchange messages via a "system queue"

### Flow of actions

* on startup, an RCC can consult its redis master file to determine the current master without the help of the RCS by checking that it's still a master (or wait for the periodic reconfigure message with the current master from the RCS)
* when the RCS finds the master to be down, it will retry a couple of times before starting a reconfiguration round
* the RCS sends all RCCs a "ping" message to check if every client is there and able to answer
* the RCCs acknowledge via a "pong" message if they can confirm the current master to be unavailable
* the RCS waits for *all* RCCs to reply via pong
* the RCS tells all RCCs to stop using the master by sending an "invalidate" message
* the RCCs acknowledge via an "invalidated" message if they can still confirm the current master to be unavailable
* the RCS waits for *all* RCCs to acknowledge the invalidation
* the RCS promotes the former slave to become the new master (by sending SLAVEOF no one)
* the RCS sends a "reconfigure" message containing the new master to every RCC
* the RCCs write the new master to their redis master file

### Configuration

See Beetle::Configuration for setting redis configuration server and client options.

Please note:
Beetle::Configuration#redis_server must be a file path (not a redis host:port string) to use the redis failover. The RCS and RCCs store the current redis master in that file, and the handlers read from it.

## How to use it

This example uses two worker servers, identified by rcc-1 and rcc-2.

Please note:
All command line options can also be given as a yaml configuration file via the --config-file option.

### On one server

Start the Redis Configuration Server:

    beetle configuration_server --redis-servers redis-1:6379,redis-2:6379 --client-ids rcc-1,rcc-2

Get help for server options:

    beetle configuration_server -h

### On every worker server

Start the Redis Configuration Client:

On first worker server:

    beetle configuration_client --client-id rcc-1

On second worker server:

    beetle configuration_client --client-id rcc-2

Get help for client options:

    beetle configuration_client -h
