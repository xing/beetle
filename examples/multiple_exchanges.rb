# multiple_exchanges.rb
# this example shows you how to create a queue that is bound to two different exchanges
# we'll create the queue foobar and bind it to the exchange foo and the exchange bar with different
# routing keys (info tidbit: different exchanges allow better loadbalacing on multi-core machines)
# your handler will then receive messages from both exchanges
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# start it with ruby attempts.rb

require "rubygems"
require File.expand_path("../lib/beetle", File.dirname(__FILE__))

# set Beetle log level to info, less noisy than debug
Beetle.config.logger.level = Logger::INFO

# setup client
client = Beetle::Client.new

# create two exchanges
client.register_exchange(:foo)
client.register_exchange(:bar)

# create a queue foobar bound to the exchange foo with the key foo
client.register_queue(:foobar, :exchange => :foo, :key => "foo")
# create an additional binding for the foobar queue, this time to the bar exchange and with the bar key
client.register_binding(:foobar, :exchange => :bar, :key => "bar")

# register two messages foo and bar remember that the defaults for exchange and key is the message name
client.register_message(:foo)
client.register_message(:bar)

# declare a handler class for message processing
# this one just gives us a debug output
client.register_handler(:foobar) do |message|
  puts "handler received: #{message.data}"
end

# and publish our two messages
client.publish(:foo, "message from foo exchange")
client.publish(:bar, "message from bar exchange")

# start the listen loop and stop listening after 0.1 seconds
# this should be more than enough time to finish processing our messages
client.listen do
  EM.add_timer(0.1) { client.stop_listening }
end

