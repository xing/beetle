---
layout: default
title: Beetle - Frequently Asked Questions
---


***Does it scale?***

Short answer: yes. Longer answer: Beetle makes it very easy to add more message
brokers. All the necessary exchanges, queues and bindings are created automatically on
each new server. Since the publishing logic randomly selects 2 out of N servers for
redundant publishing (one for failover publishing), the load should be distributed among
all brokers.

***What are the hardware requirements?***

That, of course, depends. We're currently running our messaging system on 4 moderately
fast Linux boxes: two RabbitMQ servers and two Redis servers in a master slave setup. The
Redis servers are more likely to become bottlenecks, especially if you use the
"appendfsync always" strategy for Redis appendonly log.

***How should I configure Redis?***

For the most reliable system, your Redis should be configured to use the appendlog with
the fsync always strategy.

    appendonly yes
    appendfsync always

For best results, we recommend to use an SSD for the append log.

***What is the worst failure scenario?***

It depends on the type of message you send and how the message handlers have been
configured. In the worst case you can lose one message per consumer process.
