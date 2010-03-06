# A simple usage example for Beetle
require "rubygems"
require File.expand_path(File.dirname(__FILE__)+"/../lib/beetle")

# suppress debug messages
Beetle.config.logger.level = Logger::INFO

# instantiate a client
client = Beetle::Client.new

# register a durable queue named 'test'
# this implicitly registers a durable topic exchange called 'test'
client.register_queue("test")
client.register_message("test")

# register a handler for the test message, listing on queue "test" with routing key "test"
# echoing all data sent to it
client.register_handler("test", {}) do |m|
  # send data back to publisher
  m.data
end

# start the subscriber in a separate thread
Thread.new do
  client.listen
end

n = 100
ms = Benchmark.ms do
  n.times do |i|
    content = "Hello #{i}"
    # puts "performing RPC with message content '#{content}'"
    status, result = client.rpc("test", content)
    # puts "status  #{status}"
    # puts "result  #{result}"
    # puts
    $stderr.puts "processing failure for message '#{content}'" if result != content
  end
end
printf "Runtime: %dms\n", ms
printf "Milliseconds per RPC: %.1f\n", ms/n
