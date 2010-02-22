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
# handler fails every time
$exceptions = 0
max_exceptions = 10

class Handler < Beetle::Handler
  def process
    raise "failing for the #{$exceptions += 1}. time"
  end
  def error(exception)
    logger.info "execution failed: #{exception}"
  end
end

client.register_handler("test", {:exceptions => max_exceptions, :delay => 0}, Handler)

# publish a test messages
client.publish("test", "snafu")

client.listen do
  EM.add_timer(2) { EM.stop_event_loop }
end

if $exceptions != max_exceptions + 1
  raise "something is fishy. Failed #{$exceptions} times"
end
