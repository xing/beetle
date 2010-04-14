---
layout: post
title: Introducing Beetle
---

At the end of of 2009 it became clear that the messaging system we've been using had to be
replaced with something better. We've had problems with messages getting stuck for a week
inside the message broker sometimes and on one occasion we even needed to repair it by
deleting the message store completely. This was unacceptable and we started looking around
for alternatives.

In the end, we decided that our new system should be based on a broker implementing the
AMQP protocol, for a number of reasons:

* Several broker implementations available
* Messaging system configuration is done using the protocol itself
* Excellent Ruby client library support

We chose the [RabbitMQ][rabbitmq] broker because of its good reputation in the Ruby
community and the fact that all Ruby client libraries had been developed and tested
against it. And we had already used it to build centralized Rails application logging,
which needs to handle a much higher load than what we needed for our application
messaging.

For our new messaging system, we had the following design goals:

* Important messages should not be lost if one of the message brokers dies due to a
  hardware crash
* It should be possible to upgrade broker software/hardware without system downtime
* It should be scalable
* Using the system should not require our appplication developers to be AMQP experts

RabbitMQ provides high availability through clustering of several RabitMQ nodes. Each of
the nodes has a replica of the complete messaging configuration and the cluster keeps
running even if one of the nodes goes down.

However, in the current implementation of RabbitMQ, message queues are not replicated
between the nodes of the cluster: only one node holds any given message queue. Which means
that if a node dies irrecoverably, due to a hardware crash for example, all the messages
stored in the queues on this node will be lost forever. For some of the messages we send
around in our application, this is unacceptable.

The obvious solution to this problem is to store a copy of each queue on two broker
instances and have the message consumer subscribe to both queues and discard duplicate
messages.

This sounds relatively straightforward, but an actual implementation of the
deduplification logic needs to address some nontrivial issues:

* it should work reliably across process/machine boundaries
* it should guarantee atomicity for message handler execution
* it should provide protection against misbehaving message handlers
* it should provide a way to restart failed handlers without entering an endless loop

These requirements led us to try out a persistent key value store to hold the information
we need on the consumer side: how often a message has been seen, how often we have tried
running a message handler but failed, how long we should wait before retrying and whether
some other process has already started a handler for the message (execution mutex).

Our current implementation uses [Redis][redis], as it seemed to be the simplest key value
store out there, requiring the least amount of configuration with no additional software
components necessary to get it up and running. However, we use only a small subset of
Redis' functionality, so we're by no means bound to it.

Now, after several weeks of design and implementation work, we have ported all our old
message processing code to the new infrastructure. So far everything went really smooth
and we haven't had a single problem (which is what we expected :-). Which means we have
finally reached a state where we can publish our work as a ruby gem.

So ... if you're looking for a messaging system with high availability and reliability, we
think you should give Beetle a try.

Have fun!

[rabbitmq]: http://www.rabbitmq.com/
[redis]: http://code.google.com/p/redis/
