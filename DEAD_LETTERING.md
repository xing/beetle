# Preserving Rabbit 2.x requeueing behaviour with dead letter queues

## Introduction
Rabbit 3.x changed the requeueing behaviour when messages are rejected with `reject(:requeue => true)`. In 2.x the requeued messages re-joined the queue at the end of the queue. Since 3.x they preserve their position in the queue. This can lead to throughput degradation due to Head-of-line blocking.

## Dead Letter Queues
RabbitMQ provides a [dead letter queue extension](https://www.rabbitmq.com/dlx.html). A queue can have a `dead-letter-exchange` and a `dead-letter-routing` key configured. These settings can be configured either via the queue settings or via a policy.

If a queue has those settings, they will be used when

* a message is rejected with `:requeue => false`
* the message expired due to a message ttl
* a max queue length was specified and is reached.

RabbitMQ also knows the concept of the default exchange. It's identified by an empty string. When a message has this exchange configured as `dead-letter-exchange`, the `dead-letter-routing-key` can be used to specify the queue name to which the message should be delivered.

## How Beetle uses this
When dead lettering is enabled in Beetle by setting `Beetle.config.dead_lettering_enabled` to `true`, Beetle automatically creates a dead letter queue for each queue and glues them together with RabbitMQ policies. The name of the dead letter queue is the original name suffixed with `_dead_letter`.

The original queue and its dead letter queue have a cyclic configuration. Both have the default exchange configured as the `dead-letter-exchange`. The original queue has `dead-letter-routing-key` set to the name of the dead letter queue and the dead letter queue has `dead-letter-routing-key` set to the name of the original queue.

The only difference is that the dead letter queue has a `message-ttl` configured which specifies how long the message stays in the dead letter queue, before it's republished to the original queue.

Beetle will automatically create policies on the configured Rabbit servers to bind the queues together. This has the advantage that the new behaviour can be enabled on existing queues and the message-ttls can be changed without having to delete queues.
