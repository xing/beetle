# redundant.rb
# 
# 
# 
# 
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# start it with ruby redundant.rb

require "rubygems"
require File.expand_path("../lib/beetle", File.dirname(__FILE__))

# set Beetle log level to info, less noisy than debug
Beetle.config.logger.level = Logger::INFO

# setup client
client = Beetle::Client.new

# use two servers
Beetle.config.servers = ENV["RABBITMQ_SERVERS"] || "localhost:5672, localhost:5673"
# instantiate a client
client = Beetle::Client.new

# register a durable queue named 'test'
# this implicitly registers a durable topic exchange called 'test'
client.register_queue(:test)
client.purge(:test)
client.register_message(:test, :redundant => true)

# publish some test messages
# at this point, the exchange will be created on the server and the queue will be bound to the exchange
N = 3
n = 0
N.times do |i|
  n += client.publish(:test, "Hello#{i+1}")
end
puts "published #{n} test messages"
puts

expected_publish_count = 2*N
if n != expected_publish_count
  puts "could not publish all messages"
  exit 1
end

# register a handler for the test message, listing on queue "test"
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
# this starts the event machine event loop using EM.run
# the block passed to listen will be yielded as the last step of the setup process
client.listen do
  EM.add_timer(0.2) { client.stop_listening }
end

puts "Received #{k} test messages"
raise "Your setup is borked" if N != k
