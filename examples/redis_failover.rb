# Testing redis failover functionality
require "rubygems"
require File.expand_path(File.dirname(__FILE__)+"/../lib/beetle")

# suppress debug messages
Beetle.config.logger.level = Logger::INFO
Beetle.config.redis_hosts = "localhost:6379, localhost:6380"

# instantiate a client
client = Beetle::Client.new(:servers => "localhost:5672, localhost:5673")

# register a durable queue named 'test'
# this implicitly registers a durable topic exchange called 'test'
client.register_queue(:test)
client.purge(:test)
client.register_message(:test, :redundant => true)

# publish some test messages
# at this point, the exchange will be created on the server and the queue will be bound to the exchange
N = 10
n = 0
N.times do |i|
  n += client.publish(:test, "Hello#{i+1}")
end
puts "published #{n} test messages"
puts

# check whether we wer able to pblish all messages
if n != 2*N
  puts "could not publish all messages"
  exit 1
end

# register a handler for the test message, listing on queue "test" with routing key "test"
k = 0
client.register_handler(:test) do |m|
  k += 1
  puts "Received test message from server #{m.server}"
  puts "Message content: #{m.data}"
  puts
  sleep 1
end

# hack to switch redis programmatically
class Beetle::DeduplicationStore
  def switch_redis
    slave = redis_instances.find{|r| r.server != redis.server}
    redis.shutdown rescue nil
    logger.info "Beetle: shut down master #{redis.server}"
    slave.slaveof("no one")
    logger.info "Beetle: enabled master mode on #{slave.server}"
  end
end


# start listening
# this starts the event machine event using EM.run
# the block passed to listen will be yielded as the last step of the setup process
client.listen do
  trap("INT") { client.stop_listening }
  EM.add_timer(5) { client.deduplication_store.switch_redis }
end

puts "Received #{k} test messages"
raise "Your setup is borked" if N != k
