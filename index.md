---
layout: default
title: Beetle - High Availability AMQP Messaging with Redundant Queues
---

Beetle is a ruby gem built on top of the two widely used [bunny][bunny_gem] and
[amqp][amqp_gem] client libraries. It offers the following features:

* High Availability (by using N message broker instances)
* Redundancy (by replicating queues on 2 out of N brokers)
* Simple client API (by encapsulating the message publishing / message deduplication
  logic)

The


[amqp_gem]: http://github.com/tmm1/amqp
[bunny_gem]: http://github.com/celldee/bunny
