# nonexistent_server.rb
# this example shows what happens when you try connect to a nonexistent server
#
# start it with ruby nonexistent_server.rb

require "rubygems"
require File.expand_path("../lib/beetle", File.dirname(__FILE__))

# set Beetle log level to info, less noisy than debug
Beetle.config.logger.level = Logger::INFO

Beetle.config.servers = "unknown.railsexpress.de:5672"

# setup client
client = Beetle::Client.new
client.register_queue(:test)
client.register_message(:test)

# register our handler to the message, check out the message.rb for more stuff you can get from the message object
client.register_handler(:test) {|message| puts "got message: #{message.data}"}

# start listening
# this starts the event machine event loop using EM.run
# the block passed to listen will be yielded as the last step of the setup process
client.listen do
  EM.add_timer(10) { client.stop_listening }
end

