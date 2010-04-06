---
layout: default
title: Beetle - AMQP Concepts
---

AMQP
====

AMQP is the message bus used by beetle to publish and receive messages.
This page provides you with some information to help you to understand how the wiring in
Beetle basically works. One of the major strengths of AMQP is that it
is flexibly configurable via the protocol itself. That means there is
no need for server restarts if something get's change.

Of course this introduction only covers the basics, so if you
want to fully understand how AMQP works, we can highly recommend to
read the extremly well written and understandable [AMQP
specs][amqp_specs].

The Ruby librarys currently used by Beetle are based on the 0.8
version of the spec. However, you can safely read the 0.10 version, because the
differences to 0.8 aren't critical in our case and it's a way better read.

Broker
====

The message broker is the messaging middleware between clients that
communicate via AMQP messaging. There are some popular implementation
of AMQP message brokers available. [RabbitMQ][rabbitmq_home] is our
broker of choise, because it is easy to setup, highly reliable,
resource friendly and comes with no other requirement than [Erlang][erlang_home].

Messages
======

The message is the actuall payload together with headers and a routing
key. A message is always sent with a routing key, which is used to
determine in which queue(s) a message will end up finally. The header
contains some data used by the broker and clients as well as optional
custom user data.

Exchanges
======

You never send messages directly to queues. That would actuallybe
contrary to the idea of loose cupling you generally want to achieve
with an infrastracutre heavily based on messaging. Messages are send
to exchanges instead and eventually routed to n queues. Depending on
the type of the exchange, the routing is handled by a simple routing
key, a topic routing key or simply by distributing the message to
every queue that is bound to the exchange.

Topic exchanges
-------------

In this brief introduction we'll only discuss topic exchanges since
they are currently the only type of exchanges used by Beetle.

Topic exchanges handle routing of messages by the messages routing
key. Other than the direct exchanges that check for equality of
routing keys to the keypattern with whom a queue is bound to the
exchange, topic exchanges support nested topics/namespaces for
messages.
Let's refer to the AMQP specification which has an excellent example
that describes the behaviour of topic exchanges quite well:

> The binding key is formed using zero or more tokens, with each token
> delimited by the '.' char. The binding key MUST be specified in this
> form and additionally supports special wild-card characters: '\*'
> matches a single word and '#' matches zero or more words.
>
> Thus the binding key "\*.stock.#" matches the routing keys "usd.stock"
> and "eur.stock.db" but not "stock.nasdaq".

Queues
=====

Queues are the endpoint in the message system. A client can only
receive messages if he is in any way subscribed to a queue. There is no 
way to listen to an exchange directly. Therefore the queue has to be bound 
to the exchange with a rule (the binding key) that determines which messages
get routed to the queue.

If more than one client subscribes to a queue, the broker decides
which client receives which message. So a message in a queue is only
received by one listener of the queue, never multiple ones (there are
exceptions for un-acked messages that get requeued by calling "recover"
on the connection or when the client disconnects).

[amqp_specs]: http://www.amqp.org/confluence/display/AMQP/AMQP+Specification
[rabbitmq_home]: http://www.rabbitmq.com
[erlang_home]: http://www.erlang.org
