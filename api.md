---
layout: default
title: Beetle - API
---

* [Configuration and Infrastructure][configuration]
* [Redis Failover][redis_failover]
* [The Client][client]
+ [Publishing][]
+ [Subscribing][]
+ [Exceptions][]
* [Wiring][wiring]

If you prefer code examples over written documentation, have a look at the [examples][beetle_examples] in the Beetle source which should help you to understand the basic concepts of wiring, publishing and subscribing and the specifics when dealing with different use-cases.

# Configuration and Infrastructure
<a name="configuration" />
Depending on the level of reliability and fault tolerance you need to achieve with Beetle, you have to setup your server infrastructure and the Beetle library accordingly.
If you need failover when publishing messages, you need of course at least two message brokers (If you don't need failover or redundancy, you probaply shouldn't use Beetle at all since there are simpler solutions available that might just be perfect for your requirements. [Minion][minion] is one of these). 

Having two Redis servers, running in master/slave replication mode, available allows you to switch over to the slave in case the master dies. Read more about that in the section about the [Redis Failover][redis_failover].

Beetle can be configured using Beetle.configure
    
    {% highlight ruby %}
    Beetle.config do |config|
      config.redis_hosts = "redis_host_1:6379, redis_host_2:6380"
      config.logger = Logger.new(STDOUT)
    end

    Beetle.config.servers = "message_broker_1:5672, message_broker_2:5673"
    {% endhighlight %}

Consult [the configuration documentation][config_rdoc] for a complete list of the configuration options.
    
# The Client
<a name="client" />
Beetle internally uses different classes for subscribing and publishing of messages, however this is completely transparent for the user. The class of interest for the programmer is `Beetle::Client` which is used for wiring, subscribing and publishing.
The client can be initialized with an configured instance of `Beetle::Configuration` in case you need multiple clients with different Redis and/or Brokers. Usually you can rely on the global Beetle configuration and just instantiate a client object to work with.

  {% highlight ruby %}
    client = Beetle::Client.new
  {% endhighlight %}

## Wiring
<a name="wiring" />

Wiring defines which message gets routed to which queue and which processor listens to which queue. A message needs to be configured with publishing options that manage attributes like redundancy and a name. To subscribe to a certain message a queue has to be bound to the same exchange as the message is been sent to with a binding key that matches the publishing key of the message. Let's look at the simplest example to wire a subscriber to a message called "user_created".

  {% highlight ruby %}
  client.register_queue(:user_created)
  client.register_message(:user_created)
  client.register_handler(:user_created) do |m|
    # the subscriber code
  end
  {% endhighlight %}

This registers a queue named "user_created", a message "user_created" which will be published to the exchange "user_created" with the publishing key "user_created"... you get the idea, right?

We have quite some conventions here which need to be explained. If no binding/publishing keys are explicitly configured, the queue will be bound to a exchange with a key that are named exactly like the the queue. The same applies for publishing keys and exchanges when publishing messages, of course the message name is taken for those in that case.

Of course you can configure every component involved in the wiring if you need more control over whats happening internally. Say for example you want to publish multiple messages to the same exchange and bind queues to a subset of these exchanges.

  {% highlight ruby %}
    client.configure :exchange => :user_exchange do |config|
      config.queue :general_user_subscriber, :key => "#"
      config.queue :user_creation_subscriber, :key => "user_created"

      config.message :user_created
      config.message :user_deleted, :key => "deleted_user"
      config.message :user_updated, :key => "user_has_been_updated"

      config.handler(:general_user_subscriber) { puts "Queue: general_user_subscriber" }
      config.handler(:user_creation_subscriber) { puts "Queue: user_has_been_updated" }
    end
  {% endhighlight %}

If you'd send a user_created, user_deleted and a user_updated message, the general_user_subscriber handler would receive all of them (because he is bound with the "#" as the binding key which matches every publishing key), while the user_creation handler will only receive the user_created message.

For detailed information about the wiring have a look at the rdoc for:
* [register_message](/rdoc/classes/Beetle/Client.html#M000047)
* [register_handler](/rdoc/classes/Beetle/Client.html#M000048)
* [register_exchange](/rdoc/classes/Beetle/Client.html#M000044)
* [register_queue](/rdoc/classes/Beetle/Client.html#M000045)
* [register_bindign](/rdoc/classes/Beetle/Client.html#M000046)

## Publishing
<a name="publishing" />

After a message has been configured, publishing is as simple as calling `client.publish` with the message name as the first and the payload (in form of a string) as the second argument. Of course you can send whatever string you want as the payload, as long as your subscriber/handler is able to deal with the received data.
  
  {% highlight ruby %}
    client.publish(:user_created, {:id => 42, :activated => false}.to_json)
  {% endhighlight %}


## Subscribing
<a name="subscribing" />

Beetle handlers are subscribing to queues and not to messages directly at the moment. This means that the queue has to be configured in a way that the messages that are meant to be received by the client (and only those!) will be routed into the queue.

We'll provide a simplified interface in a later release which will allow you to simplify that setup a lot and to subscribe directly to messages instead of queues (of course the handlers will still listen to queues, but the binding will be handled transparently to the user).

How a handler is registered was already briefly described in the [wiring][wiring] section of this document. The handler will be called with one argument, which is an instance of [Beetle::Message][beetle_message_rdoc]

## Exception handling
<a name="exceptions" />

The Handlers allow extensive modifications on its behavior in case an exception occurs. You can configure the maximum number of retries, the number of exceptions that occur while running the handler as well as callbacks in case of errors (and even in case the handler has finally failed / hit the maximum numbers of exceptions). Please refer to the rdoc about [register_handler](/rdoc/classes/Beetle/Client.html#M000048) and [the handler class](/rdoc/classes/Beetle/Handler.html) in general, since that's an delicate component of the Beetle architecture and effects the message processing significantly.

# Redis failover
<a name="redis_failover" />
In case the Redis server dies and you wan't to allow the consumers to switch over to the slave, you have promote the slave to the new master. The consumers will constantly try to find a new master from the ones configured. The failover and promotion of a new Redis master isn't done automatically at the moment because there are still some problems to overcome in case the old master is reachable again after he crashed or the network recovered from partitioning. One obvious risk would be that some of the consumers will switch to a new Redis instance, while others will stick to the old one. That'd be pretty much a worse case scenario because messages could get processed twice.

Until we come up with a automated solution (for example by [Leader election][leader_election]) one of the old slaves has to be made to a master manually. This can be achieved through the protocol itself (by sending the command `SLAVEOF no one`) or by changing the Redis configuration files and restarting the service. **TODO**

[beetle_examples]: http://github.com/xing/beetle/tree/master/examples/
[redis_failover]: #redis_failover
[wiring]: #wiring
[configuration]: #configuration
[client]: #client
[publishing]: #publishing
[subscribing]: #subscribing
[exceptions]: #exceptions
[minion]: http://github.com/orionz/minion
[leader_election]: http://en.wikipedia.org/wiki/Leader_election
[config_rdoc]: /rdoc/classes/Beetle/Configuration.html
[beetle_message_rdoc]: /rdoc/classes/Beetle/Message.html
