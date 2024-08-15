# What is amq-protocol

amq-protocol is an AMQP 0.9.1 serialization library for Ruby. It is not an
AMQP 0-9-1 client such as [Bunny](http://rubybunny.info): amq-protocol only handles serialization and deserialization.

If you want to write your own AMQP 0-9-1 client, this gem will handle all the serialization
needs for you, including RabbitMQ extensions to AMQP 0.9.1.


## Supported Ruby Versions

 * amq-protocol `2.3.0` only supports Ruby 2.2+.
 * amq-protocol `2.0.0` through `2.2.0` and later supports Ruby 2.0+.
 * amq-protocol `1.9.2` was the last version to support Ruby 1.8 and 1.9.


## Installation

    gem install amq-protocol


## Development

Make sure you have Python, pip and the mako templating package installed:

    pip install mako

amq-protocol uses RabbitMQ protocol code generation library that is in Python, so there is some
Python involved in the build.

To regenerate `lib/amq/protocol/client.rb` from the source (`codegen/*` files), run

    ./generate.rb

To make changes, **do not edit client.rb directly**. Instead, edit the `codegen/protocol.rb.pytemplate` and regenerate.

To run tests, use

    bundle install --binstubs
    ./bin/rspec -c spec spec


## Maintainer Information

amq-protocol is maintained by [Michael Klishin](https://github.com/michaelklishin).


## CI Status

[![Build Status](https://secure.travis-ci.org/ruby-amqp/amq-protocol.svg)](https://travis-ci.org/ruby-amqp/amq-protocol)


## Issues

Please report any issues you may find to our [Issue tracker](http://github.com/ruby-amqp/amq-protocol/issues) on GitHub.


## Mailing List

Any questions you may have should be sent to the [Ruby AMQP mailing list](http://groups.google.com/group/ruby-amqp).


## License

MIT (see LICENSE in the repository root).
