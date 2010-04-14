---
layout: default
title: Beetle - High Availability AMQP Messaging with Redundant Queues
---

### What is Beetle?

Beetle is a ruby gem built on top of the [bunny][bunny_gem] and [amqp][amqp_gem] Ruby
client libraries for AMQP. It can be used to build a messaging system with the following
features:

* High Availability (by using N message brokers)
* Redundancy (by replicating queues on all brokers)

When publishing messages, the producer can decide whether a message is published
redundantly or just sent to one of the message brokers in a round robin fashion. When
publishing redundantly, the message is sent to two brokers, with a unique message id
embedded in the message. The subscriber logic of beetle handles discarding duplicates
before invoking application code. This is achieved by storing information about the status
of message processing in a so called _deduplication store_.

### Project Status

We have completely migrated [Xing's][xing] existing (non redundant) messaging solution to
use Beetle instead. The new system has been up and running since end of March 2010 without
any problems. We've since used it to successfully parallelize and speed up a number
background tasks (e.g. SOLR indexing), to offload work from our web applications and
change our architecture to be more event driven in general.

We've reached an implemntation state where Beetle can now be used by other
projects. However, we cannot promise at the moment that the API is completely stable in
all its aspects.

### Architectural Overview

A typical configuration of a messaging system built with beetle looks like this:

<div id="arch_img">
  <a href="/beetle/images/architecture.jpg">
    <img src="/beetle/images/architecture.jpg" alt="Architecture" width="480px" height="360px"  border="0" />
  </a>
</div>


### Key System Properties

Given a system with N message brokers and a master/slave redis pair for the message
deduplication store:

* N-2 message brokers can crash or be taken down without losing redundantly queued
  messages while still maintaining the possibility of redundant publishing
  (upgrading/maintenance becomes a snap)
* N-1 messages servers can crash or be taken down without losing the ability to process
  messages (as long as the last server doesn’t crash, of course)
* If the deduplication store master crashes, the consumers will wait for it to come back
  online (or for the slave to be promoted to a master role by an administrator)
* If a consumer dies during message processing (e.g. due to a OOM kill), the message will
  be reprocessed later (if the consumer has been configured for retrying failed message
  handlers)

### Where to go next

* read our [first blog post][first_post]
* read the [FAQ page][faq_section]
* check out the [examples][examples]
* read about the [API][api]
* clone the repository and run the examples to see that it actually works
* build your own messaging system
* contribute!


[amqp_gem]: http://github.com/tmm1/amqp
[bunny_gem]: http://github.com/celldee/bunny
[first_post]: /beetle/2010/04/14/introducing-beetle.html
[faq_section]: /beetle/faq.html
[examples]: http://github.com/xing/beetle/tree/master/examples/
[api]: /beetle/api.html
[xing]: http://www.xing.com
