---
layout: default
title: Beetle - High Availability AMQP Messaging with Redundant Queues
---

### What is Beetle?
Beetle is a ruby gem built on top of the two widely used [bunny][bunny_gem] and
[amqp][amqp_gem] Ruby client libraries. It offers the following features:

* High Availability (by using N message broker instances)
* Redundancy (by replicating queues on all brokers)
* Simple client API (by encapsulating the message publishing / message deduplication
  logic)

### Architectural Overview

<div id="arch_img">
  <a href="/beetle/images/architecture.jpg">
    <img src="/beetle/images/architecture.jpg" alt="Architecture" width="100%" height="100%"  border="0" />
  </a>
</div>

### Key System Properties

* N-2 message brokers can crash without causing any problems whatsoever
  (upgrading/maintenance becomes a snap)
* N-1 messages servers can crash without affecting the system (as long as the last server
  doesn’t)
* If the deduplication store crashes, the workers will wait for it to come back online
* If a worker dies during message processing, the message will be reprocessed later

### Where to go next

* read our [first blog post][first_post]
* read the [FAQ page][faq_section]
* check out the [examples][examples]
* read about the [API][api]
* clone the repository and run the examples to see that it avtually works
* build your own messaging system
* contribute!


[amqp_gem]: http://github.com/tmm1/amqp
[bunny_gem]: http://github.com/celldee/bunny
[first_post]: /beetle/2010/04/14/introducing-beetle.html
[faq_section]: /beetle/faq.html
[examples]: http://github.com/xing/beetle/tree/master/examples/
[api]: /beetle/api.html
