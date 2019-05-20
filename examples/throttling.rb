# simple.rb
# this example shows you a very basic message/handler setup
#
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# start it with ruby simple.rb

require "rubygems"
require File.expand_path("../lib/beetle", File.dirname(__FILE__))

# set Beetle log level to info, less noisy than debug
Beetle.config.logger.level = Logger::INFO
# override default of 60 seconds
Beetle.config.throttling_refresh_interval = 5

# setup clients
client = Beetle::Client.new
client.register_queue(:test)
client.register_message(:test)
client.throttle(:test => 50)

consumer = Beetle::Client.new
consumer.register_queue(:test)
consumer.register_message(:test)

# purge the test queue
client.purge(:test)

# empty the dedup store
client.deduplication_store.flushdb

# register our handler to the message, check out the message.rb for more stuff you can get from the message object
messages_received = 0
consumer.register_handler(:test) do |message|
  sleep 0.2
  messages_received += 1
  puts "Received #{messages_received} messages"
end

interrupted = false

t = Thread.new do
  c = 0
  loop do
    break if c == 200 || interrupted
    100.times do |i|
      client.publish(:test, (c+=1).to_s)
      puts "Published message #{c}"
      sleep 0.1
    end
  end
end

trap('INT') do
  interrupted = true
  consumer.stop_listening
end

# start listening
# this starts the event machine event loop using EM.run
# the block passed to listen will be yielded as the last step of the setup process
consumer.listen do
  EM.add_periodic_timer(1) do
    consumer.stop_listening if messages_received >= 200
  end
end

t.join
