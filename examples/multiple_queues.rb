# A simple usage example for Beetle
require "rubygems"
require File.expand_path(File.dirname(__FILE__)+"/../lib/beetle")

# suppress debug messages
Beetle.config.logger.level = Logger::INFO

# instantiate a client
client = Beetle::Client.new

client.register_exchange(:foobar)

client.register_queue(:queue_1, :exchange => "foobar", :key => "foobar")
client.register_queue(:queue_2, :exchange => "foobar", :key => "foobar")

client.register_message(:foobar)

client.register_handler(:queue_1) do |message|
  puts "Queue 1"
end

client.register_handler(:queue_2) do |message|
  puts "Queue 2"
end

client.publish(:foobar, "baz")

client.listen do
  EM.add_timer(0.1) { client.stop_listening }
end

