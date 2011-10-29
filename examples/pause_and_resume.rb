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

# initially, our service is online
$online = true

# declare a handler class for message processing
# in this example we've not only overwritten the process method but also the
# error and failure methods of the handler baseclass
class Handler < Beetle::Handler

  # called when the handler receives the message - fail everytime
  def process
    puts "received message #{message.data} online=#{$online}"
    unless $online
      $client.pause_listening(:test)
      raise "offline"
    end
  end

  # called when handler process raised an exception
  def error(exception)
    puts "execution failed: #{exception}"
  end

end

# publish a decent amount of messages
# 1000.times do |i|
#   $client.publish(:test, i)
# end
# $client.stop_publishing

# register our handler to the message, configure it to our max_exceptions limit, we configure a delay of 0 to have it not wait before retrying
$client.register_handler(:test, Handler, :exceptions => 1, :delay => 0)

# and start our listening loop...
$client.listen do
  n = 0
  ptimer = EM.add_periodic_timer(0.1) do
    data = (n+=1)
    puts "publishing message #{data}"
    $client.publish(:test, data)
  end

  EM.add_periodic_timer(2) do
    $online = !$online
    $client.resume_listening(:test) if $online
  end

  EM.add_timer(10) do
    $client.pause_listening
    EM.add_timer(1) { $client.stop_listening }
  end
end
