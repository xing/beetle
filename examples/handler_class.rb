# Using Beetle::Handler classes
require "rubygems"
require File.expand_path("../lib/beetle", File.dirname(__FILE__))

# setup
Beetle.config.logger.level = Logger::INFO
client = Beetle::Client.new
client.register_queue("test")
client.register_message("test")

# store message handler results in a redis instance
STORE = Redis.new(:db => 5)
KEY = UUID4R::uuid(1)

# declare a handler class for message processing
class Handler < Beetle::Handler
  def process
    i = message.data.to_i
    logger.info "adding #{i}"
    STORE.incr(KEY,i)
  end
end

client.register_handler("test", Handler)

# publish some test messages
N = 10
n = 0
N.times {|i| n += client.publish("test", i) }
puts "published #{n} test messages"

client.listen do
  EM.add_timer(0.1) { EM.stop_event_loop }
end

# retrieve processing result and clean redis
result = STORE.get(KEY)
STORE.del KEY

puts "Result: #{result}"

raise "something is fishy" unless result = N*(N-1)/2
