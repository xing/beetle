# multiple_queues.rb
# 
# 
# 
# 
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# start it with ruby multiple_queues.rb

require "rubygems"
require File.expand_path(File.dirname(__FILE__)+"/../lib/beetle")

# set Beetle log level to info, less noisy than debug
Beetle.config.logger.level = Logger::INFO

# setup client
client = Beetle::Client.new

# this is our block configuration option, set options are used for all configs within it
# in this example all items will use: exchange => foobar and key => foobar
# so creating the two queues queue_1 and queue_2 will be bound to the same exchange
# and same key, the message foobar will also use those setting
client.configure :exchange => :foobar, :key => "foobar" do |config|
  config.queue :queue_1
  config.queue :queue_2
  config.message :foobar
  # different than other examples we use the option to configure a handler with a simple blocl
  # rather than subclassing Beetle::Handler, this allow for very easy handlers to be created
  # with a minimal amount of code
  config.handler(:queue_1) {|message| puts "received message on queue 1: " + message.data}
  # both queues will be getting the same messages ...
  config.handler(:queue_2) {|message| puts "received message on queue 2: " + message.data}
end

# ... and publish a message, we expect both queue handlers to output the message
client.publish(:foobar, "baz")

# start the listen loop and stop listening after 0.1 seconds
# this should be more than enough time to finish processing our messages
client.listen do
  EM.add_timer(0.1) { client.stop_listening }
end

