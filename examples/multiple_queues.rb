# A simple usage example for Beetle
require "rubygems"
require File.expand_path(File.dirname(__FILE__)+"/../lib/beetle")

# suppress debug messages
Beetle.config.logger.level = Logger::INFO

# instantiate a client
client = Beetle::Client.new

client.register_exchange("multiple_queues_exchange")

client.register_queue("multiple_queues_queue_1", :exchange => "multiple_queues_exchange", :key => "foobar")
client.register_queue("multiple_queues_queue_2", :exchange => "multiple_queues_exchange", :key => "foobar")

client.register_message("foobar", :exchange => "multiple_queues_exchange")

client.register_handler("foobar", :queue => "multiple_queues_queue_1") do |message|
  puts "Queue 1"
end

client.register_handler("foobar", :queue => "multiple_queues_queue_2") do |message|
  puts "Queue 2"
end

client.publish("foobar", "baz")

client.listen do
  EM.add_timer(1) { client.stop_listening }
end

