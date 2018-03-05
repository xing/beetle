# attempts_with_dead_letter_and_exponential_backoff.rb
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# start it with ruby attempts_with_dead_letter_and_exponential_backoff.rb

require "rubygems"
require File.expand_path("../lib/beetle", File.dirname(__FILE__))

require 'byebug'

# set Beetle log level to info, less noisy than debug
Beetle.config.logger.level = Logger::INFO

# setup client with dead lettering enabled
config = Beetle::Configuration.new
config.dead_lettering_enabled = true
config.dead_lettering_msg_ttl = 1000 # millis
client = Beetle::Client.new(config)
client.register_queue(:test)
client.register_message(:test)
client.register_message(:test_dead_letter)

# purge the test queue
client.purge(:test)

# empty the dedup store
client.deduplication_store.flushdb

# setup our counter
$completed = 0

# store the start time
$start_time = Time.now.to_f

ReenqueueError = Class.new(StandardError)

# declare a handler class for deferred/delayed message processing
class Handler < Beetle::Handler
  def process
    logger.info "Attempts: #{message.attempts}, Defer: #{message.defer}, Processed after: #{Time.now.to_f - $start_time}"
    logger.info message.data
    $completed += 1
  end
end
# for WORK QUEUE
client.register_handler(:test, Handler)

puts "Published 1 test message now to DEFERRED queue: #{Time.now.to_f}"
client.publish(:test_dead_letter, {foo: :late}, headers: {defer: 6})
client.publish(:test_dead_letter, {foo: :early}, headers: {defer: 3})

#client.publish_at(:test, {foo: :bar}, 6.seconds.from_now) # should look like this

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
