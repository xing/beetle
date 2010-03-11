# Demoing how exception handling works
require "rubygems"
require File.expand_path(File.dirname(__FILE__)+"/../lib/beetle")

# setup
Beetle.config.logger.level = Logger::INFO
client = Beetle::Client.new
client.register_queue("test")
client.register_message("test")
client.purge("test")
Beetle::Message.redis.flush_db

# declare a handler class for message processing
# handler fails on the first execution attempt, then succeeds
$completed = 0
class Handler < Beetle::Handler
  def process
    raise "first attempt for message #{message.data}" if message.attempts == 1
    logger.info "processing of message #{message.data} succeeded on second attempt. completed: #{$completed+=1}"
  end
  def error(exception)
    logger.info "execution failed: #{exception}"
  end
end

client.register_handler("test", Handler, :exceptions => 1, :delay => 0)

# publish some test messages
n = 0
10.times { |i| n += client.publish("test", i+1) }
puts "published #{n} test messages"

client.listen do
  trap("INT") { EM.stop_event_loop }
  timer = EM.add_periodic_timer(1) do
    if $completed == n
      timer.cancel
      EM.next_tick{EM.stop_event_loop}
    end
  end
end

puts "Handled #{$completed} messages"
if $completed != n
  raise "Did not handle the correct number of messages"
end

