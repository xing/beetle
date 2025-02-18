# Beetle

High Availability AMQP Messaging with Redundant Queues

## [!Important] Project Status

Beetle has been developed inside Xing for a long time and made available to the outside for interested people.
Due to organizational changes, we are forced to make rapid changes to the project, to address requirements we face on our internal platform.
At the same time we don't have the knowledge and resources anymore do that in the same capacitity as we did in the past.
The future of this project is unclear and it's likely to be discontinued in the future, as we move away from it internally.

All of the future development will be integrated with the master branch, and we will indicate the quality of changes using semantic versioning. 
We can't however invest any time making sure, that the changes we bring in are useful and or applicable to the broader audience.

We created a [v3.x branch](https://github.com/xing/beetle/tree/v3.x) which has been created before the latest changes starting with version 4.0.0 have been broad in.
We don't maintain this branch long term but leave it here for you to reference in a stable manner.

We will NOT publish new releases on rubygems.org, so you have to reference this repository if you want to use a version beyond 3.x.

To summarize:

* Future of project unclear, and likely to be discontinued
* Master branch will change more frequently
* New releases will NOT be published on public rubygems.org
* [v3.x branch](https://github.com/xing/beetle/tree/v3.x) is available, and remains available for the time being, but we don't maintain it


## About

Beetle grew out of a project to improve an existing ActiveMQ based messaging
infrastructure. It offers the following features:

* High Availability (by using multiple message broker instances)
* Redundancy (by replicating queues)
* Simple client API (by encapsulating the publishing/ deduplication logic)


## Release notes

See [RELEASE_NOTES.md](./RELEASE_NOTES.md)

## Usage

### Configuration

    # configure machines

    Beetle.config do |config|
      config.servers = "broker1:5672, broker2:5672"
      config.redis_server = "redis1:6379"
    end

    # instantiate a beetle client

    b = Beetle::Client.new

    # configure exchanges, queues, bindings, messages and handlers

    b.configure do
      queue :test
      message :test
      handler(:test) { |message| puts message.data }
    end

### Publishing

    b.publish :test, "I'm a test message"

### Subscribing

    b.listen_queues

### Examples

Beetle ships with a number of [example scripts](http://github.com/xing/beetle/tree/master/examples/).

The top level Rakefile comes with targets to start several RabbitMQ and redis instances
locally. Make sure the corresponding binaries are in your search path. Open four new shell
windows and execute the following commands:

    rake rabbit:start1
    rake rabbit:start2
    rake redis:start:master
    rake redis:start:slave

## Prerequisites

To set up a redundant messaging system you will need
* at least 2 AMQP servers (we use [RabbitMQ](http://www.rabbitmq.com/))
* at least one [Redis](http://github.com/antirez/redis) server (better are two in a
  master/slave setup, see [REDIS_AUTO_FAILOVER.md](./REDIS_AUTO_FAILOVER.md))

## Test environment

For testing purposes, you will need a MySQL database with the database
`beetle_test` created. This is needed to test special cases in which
Beetle handles the connection with ActiveRecord:

     mysql -e 'create database beetle_test;'

You also need a Redis instance running. The default configuration of Redis will work:

    redis-server

If you want to run the integration tests you need GO installed and you
will need to build the beetle binary. We provide a Makefile for this
purpose, so simply running

    make

should suffice.

## Gem Dependencies

At runtime, Beetle will use
* [bunny](http://github.com/ruby-amqp/bunny)
* [redis](http://github.com/redis/redis-rb)
* [amqp](http://github.com/ruby-amqp/amqp)
  (which is based on [eventmachine](http://github.com/eventmachine/eventmachine))
* [daemons](http://daemons.rubyforge.org/)
* [activesupport](https://github.com/rails/rails/tree/master/activesupport)

For development, you'll need
* [mocha](http://github.com/floehopper/mocha)
* [cucumber](http://github.com/aslakhellesoy/cucumber)
* [daemon_controller](http://github.com/FooBarWidget/daemon_controller)
* [consul](https://www.consul.io/downloads.html)

For tests, you'll need
* [activerecord](https://github.com/rails/rails/tree/master/activerecord)
* [mysql2](https://github.com/brianmario/mysql2/)

Dependencies are managed by `bundler`.

If you want to use a `redis-rb` version after 5.0.0, you must add the
`hiredis-client` gem to your application.


## Authors

[Stefan Kaes](http://github.com/skaes),
[Pascal Friederich](http://github.com/paukul),
[Ali Jelveh](http://github.com/dudemeister),
[Bjoern Rochel](http://github.com/bjro) and
[Sebastian Roebke](http://github.com/boosty).

You can find out more about our work on our [dev blog](http://devblog.xing.com).

Copyright (c) 2010-2019 [XING AG](http://www.xing.com/)

Released under the MIT license. For full details see MIT-LICENSE included in this
distribution.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Hack along and test your code.
4. Commit your changes (`git commit -am 'Add some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create new Pull Request

Don't increase the gem version in your pull requests. It will be done after merging the request,
to allow merging of pull requests in a flexible order.

## Compiling beetle and running tests

In order to execute the unit tests, you need Ruby, a running rabbitmq server, a running
redis-server, a running mysql server and a runnning consul server.

In addition, beetle ships with a cucumber feature to test the automatic redis failover as
an integration test. For this you need a recent Go installation in order to compile the
beetle go binary. Just invoke `make` in the top level directory.

There are two ways to start the required test dependencies: using `docker compose` or
starting the services manually.

### Testing with docker compose

Open a separate terminal window and run

     docker compose pull

followed by

     docker compose up

This will start mysql, two redis servers, two RabbitMQ instances and a single consul
development node.

Note: make sure to wait until all services are properly started.


## Testing with  locally installed services

The top level Rakefile comes with targets to start several RabbitMQ instances locally.
Make sure the corresponding binaries are in your search path. Open three shell windows and
execute the following command:

    rake rabbit:start1

and

   rake redis:start:master

as well as

   rake consul:start

Then you can run the cucumber feature by running:

    cucumber

or

    rake cucumber

Note: Cucumber will automatically run after the unit tests when you run `rake` without
arguments.


## How to release a new gem version

Update [RELEASE_NOTES.md](./RELEASE_NOTES.md)!

We use [semantic versioning](http://semver.org/) and create a git tag
for each release.

Edit `lib/beetle/version.rb` and
`go/src/github.com/xing/beetle/version.go` to set the new version
number (`Major.Minor.Patch`).

In short (see [semver.org](http://semver.org) for details):

* *Major* version MUST be incremented if any backwards incompatible changes
  are introduced to the public API.
* *Minor* version MUST be incremented if new, backwards compatible functionality
  is introduced to the public API. It MUST be incremented if any public API
  functionality is marked as deprecated.
* *Patch* version MUST be incremented if only backwards compatible bug fixes
  are introduced.

Then use `rake release` which will create the git tag and upload the
gem to github.com:

    bundle exec rake release

The generated gem is located in the `pkg/` directory.

In order to build go binaries and upload the docker container with the
beetle GO binary to docker hub, run

    make release

This will upload the go binaries to https://github.com/xing/beetle/
and push the beetle container to
https://hub.docker.com/r/xingarchitects/gobeetle/.

Run

    make tag push TAG=X.X.X

to tag and push the container with a specific version number.
