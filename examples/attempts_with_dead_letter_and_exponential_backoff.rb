# attempts_with_dead_letter_and_exponential_backoff.rb
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# start it with ruby attempts_with_dead_letter_and_exponential_backoff.rb

require "rubygems"
require File.expand_path("../lib/beetle", File.dirname(__FILE__))

# set Beetle log level to info, less noisy than debug
Beetle.config.logger.level = Logger::INFO

# setup client with dead lettering enabled
config = Beetle::Configuration.new
config.dead_lettering_enabled = true
config.dead_lettering_msg_ttl = 1000 # millis
client = Beetle::Client.new(config)
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
# handler fails on the first execution attempt, then succeeds
class Handler < Beetle::Handler
  # called when the handler receives the message, fails on first two attempts
  # succeeds on the next and counts up our counter
  def process
    logger.info "Attempts: #{message.attempts} for `#{message.data}`, Base Delay: #{message.delay}, Processed at: #{Time.now.to_f - $start_time}"
    raise "attempt #{message.attempts} for message #{message.data}" if message.attempts < $exceptions_limit
    logger.info "processing of message #{message.data} succeeded on attempt #{message.attempts}. completed: #{$completed += 1}"
  end

  # called when handler process raised an exception
  def error(exception)
    logger.info "execution failed: #{exception}"
  end
end

# register our handler to the message, configure it to our max_attempts limit, we configure a (base) delay of 0.5
client.register_handler(:test, Handler, exceptions: $exceptions_limit, delay: 1, max_delay: 10)
puts "publish 2 test messages with payload `FIRST` and `SECOND`"
# publish test messages
client.publish(:test, "FIRST")
client.publish(:test, "SECOND")

# start the listening loop
client.listen do
  # catch INT-signal and stop listening
  trap("INT") { client.stop_listening }
  # we're adding a periodic timer to check whether all 10 messages have been processed without exceptions
  timer = EM.add_periodic_timer(1) do
    if $completed == 2
      timer.cancel
      client.stop_listening
    end
  end
end

puts "Handled #{$completed} messages"
if $completed != 2
  raise "Did not handle the correct number of messages"
end
