# handler.rb
# this example shows you how to create a simple Beetle::Handler to process your messages
#
#
# 
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# start it with ruby handler_class.rb

require "rubygems"
require File.expand_path("../lib/beetle", File.dirname(__FILE__))

# set Beetle log level to info, less noisy than debug
Beetle.config.logger.level = Logger::INFO

# setup client
client = Beetle::Client.new
client.register_queue(:test)
client.register_message(:test)

# purge the test queue
client.purge(:test)

# empty the dedup store
client.deduplication_store.flushdb

# setup our counter
$counter = 0

# declare a handler class for message processing
# this is a very basic example, subclass your own implementation
# process is the only method required and the message accessor is
# already implemented - see message.rb for more documentation on what you
# can do with it
class Handler < Beetle::Handler

  # called when the handler receives the message
  def process
    i = message.data.to_i
    logger.info "adding #{i}"
    $counter += i
  end

end

# when you have several messages you want to handle
# within the same handler class you may want to use
# the "handle" method instead of overriding the
# process method
class AnotherHandler < Beetle::Handler
  handle "very.important.message" do |payload|
    # handle message
  end

  handle "another.important.message", "same.handler.twice" do |payload|
    # handle message
  end
end

# register our handler to the message
client.register_handler(:test, Handler)

# publish 10 test messages
message_count = 10
published     = 0
message_count.times {|i| published += client.publish(:test, i) } # publish returns the number of servers the message has been sent to
puts "published #{published} test messages"

# start our listening loop and stop it with a timer -
# the 0.1 figure should be well above the time necessary to handle
# all 10 messages
client.listen do
  EM.add_timer(0.1) { client.stop_listening }
end

# the counter should now be message_count*(message_count-1)/2 if it's not something went wrong
puts "Result: #{$counter}"
raise "something is fishy" unless $counter == message_count*(message_count-1)/2
