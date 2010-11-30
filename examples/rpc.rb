# A simple usage example for Beetle
require "rubygems"
require File.expand_path(File.dirname(__FILE__)+"/../lib/beetle")

# suppress debug messages
Beetle.config.logger.level = Logger::DEBUG
Beetle.config.servers = "localhost:5672, localhost:5673"
# instantiate a client

client = Beetle::Client.new

# register a durable queue named 'echo'
# this implicitly registers a durable topic exchange called 'echo'
client.register_queue(:echo)
client.register_message(:echo)

if ARGV.include?("--server")
  # register a handler for the echo message, listing on queue "echo"
  # echoing all data sent to it
  client.register_handler(:echo) do |m|
    # send data back to publisher
    m.data
  end

  # start the subscriber
  client.listen do
    puts "started echo server"
    trap("INT") { puts "stopped echo server"; client.stop_listening }
  end
else
  n = 100
  ms = Benchmark.ms do
    n.times do |i|
      content = "Hello #{i}"
      # puts "performing RPC with message content '#{content}'"
      status, result = client.rpc(:echo, content)
      # puts "status  #{status}"
      # puts "result  #{result}"
      # puts
      $stderr.puts "processing failure for message '#{content}'" if result != content
    end
  end
  printf "Runtime: %dms\n", ms
  printf "Milliseconds per RPC: %.1f\n", ms/n
end

