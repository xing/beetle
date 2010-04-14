# handling_exceptions.rb
# this examples shows you how beetle retries and exception handling works in general
# as you will see in the Beetle::Handler example every message will raise an exception
# once and be succesful on the next attempt, the error callback is called on every process
# exception
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# start it with ruby attempts.rb

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
$completed = 0

# declare a handler class for message processing
# handler fails on the first execution attempt, then succeeds
class Handler < Beetle::Handler

  # called when the handler receives the message, fails on first attempt
  # succeeds on the next and counts up our counter
  def process
    raise "first attempt for message #{message.data}" if message.attempts == 1
    logger.info "processing of message #{message.data} succeeded on second attempt. completed: #{$completed+=1}"
  end

  # called when handler process raised an exception
  def error(exception)
    logger.info "execution failed: #{exception}"
  end

end

# register our handler to the message, configure it to our max_exceptions limit, we configure a delay of 0 to have it not wait before retrying
client.register_handler(:test, Handler, :exceptions => 1, :delay => 0)

# publish 10 test messages
n = 0
10.times { |i| n += client.publish(:test, i+1) } # publish returns the number of servers the message has been sent to
puts "published #{n} test messages"

# start the listening loop
client.listen do
  # catch INT-signal and stop listening
  trap("INT") { client.stop_listening }
  # we're adding a periodic timer to check wether all 10 messages have been processed without exceptions
  timer = EM.add_periodic_timer(1) do
    if $completed == n
      timer.cancel
      client.stop_listening
    end
  end
end

puts "Handled #{$completed} messages"
if $completed != n
  raise "Did not handle the correct number of messages"
end

