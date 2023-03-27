# Release Notes

## Version 3.5.7
* Require bunny versions (`~> 0.7.13`) that work for Ruby 3.2 out of
  the box.

## Version 3.5.6
* Fixed that publishing additional AMQP headers crashed the publisher
  since Ruby 3.2.0, due to missing Fixnum class.

## Version 3.5.5
* Support Redis version 5.x.
* If you want to use a `redis-rb` gem version after 5.0.0, you must
  add the `hiredis-client` gem to your application Gemfile.
* Support setting Redis timeouts in the Beetle configuration. Default
  is 5.0 seconds for all timeouts as this is the default for redis gem
  versions before 5.0.0.

## Version 3.5.4
* Restrict redis gem to have a version before 5.0 as this version is incompatible

## Version 3.5.3
* Fixed that message publishing was never retried on Errno::ETIMEDOUT

## Version 3.5.2
* Fixed that not all available Redis servers where turned into proper slaves during a
  master switch

## Version 3.5.1
* Remove blank entries from server list strings
* Make sure not to subscribe to any server twice

## Version 3.5.0
* expose publisher method to setup queues/policies ahead of use

## Version 3.4.3
* optimize declaration of queues with many bindings

## Version 3.4.2
* Updated amq-protocol gem to version 2.3.2.
* Fixed a rare race condition on message handler timeouts.

## Version 3.4.1
* Updated amq-protocol gem to version 2.3.1.

## Version 3.4.0
* Require redis gem version 4.2.1. This version changes the exists to check for the
  existence of multiple keys, return the number of keys in the list that exist. This
  requires at least redis gem version 4.2.0, but 4.2.1 contains a bug fix for said
  command.

## Version 3.3.12
* Support queue level declaration of dead letter queue message TTL.

## Version 3.3.11
* Fixed that dead lettering only works correctly with global config option.

## Version 3.3.10
* Support configuring RabbitMQ write timeout.

## Version 3.3.9
* Reduce the number of queue policies created on the servers by allowing
  the spefication of a default broker policy. You need to install the
  default policy with a priority of zero to match all queues ever
  created. This feature is optional.

## Version 3.3.8
* Avoid needless put call when updating queue policies.
  It seems the additional call to get the current definition of a policy
  is to be preferred over relying on the idempotency of the PUT call.
  This helps when adding a new fresh server to a beetle cluster: import
  the definitions of one of the existing nodes on the fresh node before
  actually adding it to the list of servers in the client's beetle config..

## Version 3.3.7
* Increased default http api read timeout to handle large server better.

## Version 3.3.6
* Fixed a redis connection leak in gobeetle.

## Version 3.3.5
* Support synchronous queue policy creation.

## Version 3.3.4
* Track publishing policy options metrics.

## Version 3.3.3
* Broken.

## Version 3.3.2
* Changed order of queue policy application to avoid ahead of line blocking in dead letter
  queues.

## Version 3.3.1
* It seems that there is a certain preference on connection level when
  selecting the next message to process. We try to protect against
  such bias by connecting in random order.

## Version 3.3.0
* protect against duplicate handler execution by keeping the status of
  handler exectution for both redundant and non-redundant messages in
  the dedup store for a configurable time window. The config option
  is named redis_status_key_expiry_interval. Note that this will
  significantly increase the cpu load and memory usage of the Redis
  server for applications using a large number of non-redundant
  messages. This feature is turned off by default, but we will
  activate it with the next major release (4.0.0).

## Version 3.2.0
* added currently processed message to the handler pre-processing step

## Version 3.1.0
* added more debug log statements
* added new callbacks on class Beetle::Handler:
  * pre_process is called before any message processing commences
  * post_process is called after all processing has been completed
  these handlers can be used for logging purposes (such as logjam
  integration)

## Version 3.0.0

* provide client method to setup queues and queue policies.
  Setting up queue policies on demand in publisher and subscriber is OK
  for a small number of queues, publishers and subscribers. But the HTTP
  API of RabbitMQ doesn't scale all that well, so that a large number
  of HTTP calls to set up queue policies can in fact crash a server.
* allow queue mode specification and dead lettering specification on a
  per queue basis.
* change policy setup to be asynchronous, on demand in publisher and
  consumer. Users have to run a processors to listen to messages and
  call setup_queue_policies! with the parses JSON paylod of the
  message.
* store redis gc stats in redis and display them in the configuration
  server web UI
* config server: store current master server in consul, if consul
  config has been provided.
* config server: server correctly updates configured client ids when
  they change in consul.
* don't create dead letter queues when using the trace functionality
* make sure to clean dedup store when ack_count is larger than 2
* added dump_expiries command to beetle to dump dediplication store
  expiry times.
* added delete_queue_keys command to beetle to allow deletion of
  excess dedup store entries for a given queue.

## Version 2.3.2
* config server: fixed a race condition when accessing server state.
  HTTP requests run in threads separate from the server dispatcher
  thread and thus can cause race conditions/crashes when accessing
  server state. Solved this by adding a closure evaluator to the
  dispatcher.

## Version 2.3.1
* updated amqp and amq-protocol requirements in ruby client.
* fixed that a change in consul endpoint was not properly handled by
  the beetle configuration client.

## Version 2.3.0
* redis failover: support multiple redis failover instances. This has
  required a change in the redis master file format. The master file
  content is now either the old format (host:port) for systems using a
  single redis failover system or a mapping from system names to
  host:port combinations. For example,
  "system1/master1:6379\nsystem2/master" specifies to systems with
  their corresponding redis masters. Beetle client uses the configured
  system name to tind the master it should use.
* support lazy queues: setting :lazy_quques_enabled on the beetle
  cofiguration will enable queue_mode: "lazy" for all queues of
  declared on the beetle client.
* improved calculation of channel close an connection disconnect
  timeouts for beetle publisher to avoid warnings in RabbitMQ logs.
* use SecureRandom.uuid instead of UUID4R::uuid(4) if UUID4R cannot
  be loaded.

## Version 2.2.4
* redis failover: prevent starting a new master switch while one is running

## Version 2.2.3
* redis failover: server logs errors when redis oparations fail

## Version 2.2.2

* Reset redis configuration server state when master becomes available during
  pinging or invalidating.  Unlike the former ruby implementation, the go code
  continues checking redis availability during pinging or invalidating. However,
  the code did not reset state properly, leading the UI to display 'switch in
  progress' when in fact there wasn't.

## Version 2.2.1
* Subscriber exits with meaningful error log on possible authentication failures.

## Version 2.2.0

* Support specifying a whitelist of retriable exceptions when registering a
  message handler. Exceptions which are not on the list will be regarded as
  irrecoverable failures.

## Version 2.1.2

* Fixed that redis key GC would never complete when a key scheduled
  for GC was deleted by a consumer before the collector could retrieve
  its expiry date.
* Fixed tha redis key GC would crash on malformed keys.
* Added method to collect keys specified in a file.


## Version 2.1.1

* Support redis failover with less than 100% acknowlegment from failover clients.

## Version 2.1.0

* Support exponential backoff when delaying messages using 'max_delay: int' option.

## Version 2.0.2

* fixed incorrect computation of responsiveness threshold in
  configuration server

## Version 2.0.1

* fix for beetle command not geting stuck when connecting to
  configuration server
* configuration server displays last seen times in a human readable format

## Version 2.0.0

* beetle command has been rewritten in Go
* garbage collecting redis keys now uses the redis SCAN command

## Version 1.0.4

* use amqp protocol version 0.9 by default for publishers

## Version 1.0.3

* fixed that publisher did not allow specifying message properties

## Version 1.0.2

* relax hiredis requirements to >= 0.4.5

## Version 1.0.1

* don't try to connect on publisher shutdown

## Version 1.0.0

* introduced semantic versioning
* upgraded gems used for devloping beetle
* upgraded amqp gem to version 1.6.0 and amq-protocol to 2.0.1
* relaxed requirements on redis and hiredis versions
* support setting prefetch count for subscriber

## Version 0.4.12

* Don't log warnings when publishing redundantly and only
  one server has been configured

## Version 0.4.11

* Automatically close open publisher sockets at program exit

## Version 0.4.10

* Publisher handles nil and symbols as values in headers correctly

## Version 0.4.9

* Allow redis_configuration_client to run in the foreground (useful
  for docker)

## Version 0.4.8

* unseen clients need to be an array

## Version 0.4.7

* list clients which have never sent a ping in the failover server UI

## Version 0.4.6

* Publish activesupport notifications to support performance measurements

## Version 0.4.5

* Starting mutliple redis failover clients is now prohibited by
  default. This behavior can be overriden using
  "beetle configuration_client start -- --multiple"

## Version 0.4.4

* added command to show beetle version: "beetle --version"
* configuration server tracks ids of unknown clients
* configuration clients now sends heartbeats
* configuration server tracks last seen times of clients, based on heartbeat

## Version 0.4.3

* fixed a race condition which could lead to duplicate message processing
* fixed eventmachine shutdown sequence problem, which led to ACKs
  occasionally being lost due to writing to a closed socket, which in
  turn caused messages to be processed twice
* stop_listening now always triggers the subscribe shutdown sequence
  via a eventmachine timer callback, if the eventmachine reactor is running

## Version 0.4.2

* Fail hard on missing master file
* Set message timestamp header

## Version 0.4.1

* Require newer bunny version (0.7.10) to fix publishing of messages larger than frame_max

## Version 0.4.0

* Added optional dead lettering feature to mimic RabbitMQ 2.x requeueing behaviour on RabbitMQ 3.x

## Version 0.3.14

* switched message id generation to use v4 uuids

## Version 0.3.0

* redis master file contents now correctly reflects the state of the running configuration server
* allow accelerating master switch via POST to redis configuration server
* embedded http server into the redis configuration server (port 8080)
* fixed a problem with redis shutdown command
* upgraded to redis 2.2.2
* upgraded to amqp gem version 0.8 line
* use hiredis as the redis backend, which overcomes lack of proper time-outs in the "generic" redis-rb
  gem for Ruby 1.9
* use fully qualified hostnames to identify redis configuration clients

## Version 0.2.9.8

* since version 2.0, RabbitMQ supports Basic.reject(:requeue => true). we use it now too,
  because it enhances performance of message processors. this means of course, you can
  only use beetle gem versions >= 0.2.9.8 if your rabbitmq brokers are at least version 2.0.
* publishing timeout defaults to 0 to avoid extreme message loss in some cases


## Version 0.2.9.7

* use new bunny_ext gem and allow specification of global publishing timeouts
* registering a message now automatically registers the corresponding exchange
* don't try to bind queues for an exchange hich has no queue
* ruby 1.9.2 compatibility fixes

## Version 0.2.9

* Beetle::Client now raises an exception when it fails to publish a message to at least 1 RabbitMQ server
* Subscribers are now stopped cleanly to avoid 'closed abruptly' messages in the RabbitMQ server log

## Version 0.2.6

* Set dependency on ActiveSupport to 2.3.x since it ain't compatible to version 3.x yet
* Publishers catch a wider range (all?) of possible exceptions when publishing messages
* Redis Configuration Servers detect and warn when unknown Redis Configuration Clients connect

## Version 0.2.5

Added missing files to gem and rdoc

## Version 0.2.4

Log and send a system notification when pong message from unknown client received.

## Version 0.2.2

Patch release which upgrades to redis-rb 2.0.4. This enables us to drop our redis monkey
patch which enabled connection timeouts for earlier redis versions. Note that earlier
Beetle versions are not compatible with redis 2.0.4.

## Version 0.2.1

Improved error message when no rabbitmq broker is available.

## Version 0.2

This version adds support for automatic redis deduplication store failover (see separate
file REDIS_AUTO_FAILOVER.rdoc).

### User visible changes

* it's possible to register auto deleted queues and exchanges
* Beetle::Client#configure returns self in order to simplify client setup
* it's possible to trace specific messages (see Beetle::Client#trace)
* default message handler timeout is 10 minutes now
* system wide configuration values can be specified via a yml formatted configuration
  file (Beetle::Configuration#config_file)
* the config value redis_server specifies either a single server or a file path (used
  by the automatic redis failover logic)

### Fugs Bixed

* handle active_support seconds notation for handler timeouts correctly
* error handler was erroneously called for expired messages
* subscribers would block when some non beetle process posts an undecodable message

### Gem Dependency Changes

* redis needs to be at least version 2.0.3
* we make use of the SystemTimer gem for ruby 1.8.7

## Version 0.1

Initial Release
