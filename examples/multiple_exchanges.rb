# A simple usage example for Beetle
require "rubygems"
require File.expand_path(File.dirname(__FILE__)+"/../lib/beetle")

# suppress debug messages
Beetle.config.logger.level = Logger::INFO

# instantiate a client
client = Beetle::Client.new

client.register_exchange(:foo)
client.register_exchange(:bar)

client.register_queue(:foobar, :exchange => :foo, :key => "foo")
client.register_binding(:foobar, :exchange => :bar, :key => "bar")

client.register_message(:foo)
client.register_message(:bar)

client.register_handler(:foobar) do |message|
  puts "foobar: #{message.data}"
end

client.publish(:foo, "from foo")
client.publish(:bar, "from bar")

client.listen do
  EM.add_timer(0.1) { client.stop_listening }
end

