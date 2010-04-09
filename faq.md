---
layout: default
title: Beetle - Frequently Asked Questions
---

***When should I not use Beetle?***

If it's not fast enough for your use case. For example, we use RabbitMQ directly for our
application logging. Other examples: streaming videos through your messaging system, using
RabbitmMQ as a reverse http proxy.

***What does High Availability mean?***

It mostly means 24/7 message publishing. This is important for us, as we send most
messages from our web applications to a large array of background processors. For the
receiver side it means that some message consumers might pause for a short period of time
if the message deduplication store becomes temporarily unavailable.

***Does it scale?***

Short answer: yes. Longer answer: Beetle makes it very easy to add more message brokers to
an existing messaging system. All the necessary exchanges, queues and bindings are created
automatically on each new server. Since the publishing logic randomly selects 2 out of N
servers for redundant publishing (one for failover publishing), the load should be
distributed relatively evenly among all brokers. If the message deduplication store
becomes a bottleneck, you can partition the queues and assign a separate deduplication
store to each partition.

***Why aren't all messages sent redundantly?***

Because not all messages are equally important. Using redundancy only for those messages
which need it increases system throughput, for two reasons:

* redundant messages have to be sent to two servers, whereas non redundant messages are
  sent to only one
* processing non redundant messages does does not require accessing the deduplication
  store, unless you specify the corresponding message handler to be retriable (see
  [messsage handler logic][message_handlers])

***What are the hardware requirements?***

That, of course, depends. We're currently running our messaging system on five moderately
fast Linux boxes: three RabbitMQ servers and two Redis servers in a master slave
setup. This is the minimum number of machines if you want to be able to guarantee that
messages can always be published redundantly, even if one of the message brokers dies. In
this setup, the Redis master server is most likely to become a bottleneck, especially if
you use the "appendfsync always" strategy for the Redis appendonly log. For best
performance, we recommend to use a separate partition on a really fast disk for the append
log file.

***What is the worst failure scenario?***

It depends on the type of message and how the message handlers have been configured. For
non redundant messages the worst failure is an irrecoverable message broker crash. All non
redundant messages stored on the broken server will be lost. Redundantly queued messages
are unaffected by message broker crashes. For those messages, the worst thing that can
happen is an irrecoverable Redis server crash. A Redis server crash means that some
information on the state of message processing can get lost, which could lead to a small
number of messages being processed twice or not at all. Please refer to the description of
the [messsage handler logic][message_handlers].

***Isn't the Redis server a single point of failure?***

Yes. But the impact of an irrecoverable failure on a Redis server machine is much smaller
than the impact of a irrecoverable broker failure in a single message broker system.

Nevertheless, it's a weakness of the current system and we're thinking of ways to
eliminate it.

***How should I configure Redis?***

For the most reliable system, your Redis server should be configured to use the appendlog
with the fsync always strategy.

        appendonly yes
        appendfsync always


[message_handlers]: /beetle/message_handlers.html
