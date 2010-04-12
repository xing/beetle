# A simple usage example for Beetle
require "rubygems"
require File.expand_path(File.dirname(__FILE__)+"/../lib/beetle")

# pass --redundant to this script to use redundant messaging
redundant = ARGV.include?('--redundant')

# suppress debug messages
Beetle.config.logger.level = Logger::INFO
# use two servers
Beetle.config.servers = "localhost:5672, localhost:5673"
# instantiate a client
client = Beetle::Client.new

# register a durable queue named 'test'
# this implicitly registers a durable topic exchange called 'test'
client.register_queue(:test)
client.purge(:test)
client.register_message(:test, :redundant => redundant)

# publish some test messages
# at this point, the exchange will be created on the server and the queue will be bound to the exchange
N = 3
n = 0
N.times do |i|
  n += client.publish(:test, "Hello#{i+1}")
end
puts "published #{n} test messages"
puts

expected_publish_count = redundant ? 2*N : N
if n != expected_publish_count
  puts "could not publish all messages"
  exit 1
end

# register a handler for the test message, listing on queue "test" with routing key "test"
k = 0
client.register_handler(:test) do |m|
  k += 1
  puts "Received test message from server #{m.server}"
  puts m.msg_id
  p m.header
  puts "Message content: #{m.data}"
  puts
end

# start listening
# this starts the event machine event using EM.run
# the block passed to listen will be yielded as the last step of the setup process
client.listen do
  EM.add_timer(0.1) { EM.stop_event_loop }
end

puts "Received #{k} test messages"
raise "Your setup is borked" if N != k
