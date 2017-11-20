# attempts_with_exponential_backoff.rb
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# start it with ruby attempts_with_exponential_backoff.rb

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
$exceptions_limit = 4

# store the start time
$start_time = Time.now.to_f

# declare a handler class for message processing
# handler fails on the first $exceptions_limit-1 execution attempts, then succeeds
class Handler < Beetle::Handler

  # called when the handler receives the message
  # succeeds on the next and counts up our counter
  def process
    logger.info "Attempts: #{message.attempts}, Base Delay: #{message.delay}, Processed at: #{Time.now.to_f - $start_time}"
    raise "Attempt #{message.attempts} for message #{message.data}" if message.attempts < $exceptions_limit
    logger.info "Processing of message #{message.data} succeeded on attempt #{message.attempts}. completed: #{$completed += 1}"
  end

  # called when handler process raised an exception
  def error(exception)
    logger.info "Execution failed: #{exception}"
  end
end

# register our handler to the message, configure it to our max_attempts limit, we configure a (base) delay of 0.5
client.register_handler(:test, Handler, exceptions: $exceptions_limit, delay: 0.2, exponential_back_off: true)

# publish test messages
client.publish(:test, 1) # publish returns the number of servers the message has been sent to
puts "Published 1 test message"

# start the listening loop
client.listen do
  # catch INT-signal and stop listening
  trap("INT") { client.stop_listening }
  # we're adding a periodic timer to check whether all messages have been processed without exceptions
  timer = EM.add_periodic_timer(1) do
    if $completed == 1
      timer.cancel
      client.stop_listening
    end
  end
end

puts "Handled #{$completed} messages"
if $completed != 1
  raise "Did not handle the correct number of messages"
end

