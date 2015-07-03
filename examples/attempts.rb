# attempts.rb
# this example shows you how to use the exception limiting feature of beetle
# it allows you to control the number of retries your handler will go through
# with one message before giving up on it
#
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# start it with ruby attempts.rb

require "rubygems"
require File.expand_path("../lib/beetle", File.dirname(__FILE__))

# set Beetle log level to info, less noisy than debug
Beetle.config.logger.level = Logger::INFO

# setup client
$client = Beetle::Client.new
$client.register_queue(:test)
$client.register_message(:test)

# purge the test queue
$client.purge(:test)

# empty the dedup store
$client.deduplication_store.flushdb

# we're starting with 0 exceptions and expect our handler to process the message until the exception count has reached 10
$exceptions = 0
$max_exceptions = 10

# declare a handler class for message processing
# in this example we've not only overwritten the process method but also the
# error and failure methods of the handler baseclass
class Handler < Beetle::Handler

  # called when the handler receives the message - fail everytime
  def process
    logger.info "received message with routing key: #{message.routing_key}"
    death = message.header.attributes[:headers]["x-death"]
    if death
      logger.info "X-DEATH: died #{death.first["count"]} times"
      death.each {|d| logger.debug d}
    end
    raise "failed #{$exceptions += 1} times"
  end

  # called when handler process raised an exception
  def error(exception)
    logger.info "execution failed: #{exception}"
  end

  # called when the handler has finally failed
  # we're stopping the event loop so this script stops after that
  def failure(result)
    super
    EM.add_timer(1){$client.stop_listening}
  end
end

# register our handler to the message, configure it to our max_exceptions limit, we configure a delay of 0 to have it not wait before retrying
$client.register_handler(:test, Handler, :exceptions => $max_exceptions, :delay => 0)

# publish a our test message
$client.publish(:test, "snafu")

# and start our listening loop...
$client.listen

# error handling, if everything went right this shouldn't happen.
if $exceptions != $max_exceptions + 1
  raise "Something is fishy. Failed #{$exceptions} times"
end
