# headers.rb
# this example shows using custom headers
#
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# start it with ruby headers.rb

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

# register our handler to the message, check out the message.rb for more stuff you can get from the message object
client.register_handler(:test) {|message| puts "got message with headers: #{message.header.attributes[:headers]}"}

# publish our message (NOTE: empty message bodies don't work, most likely due to bugs in bunny/amqp)
puts client.publish(:test, 'bam', :headers => {
  :header1 => "foo",
  :header2 => 42,
  :header3 => 0.1,
  :header4 => :foo, # will be converted to string
  :header5 => nil   # will be filtered out
})

# start listening
# this starts the event machine event loop using EM.run
# the block passed to listen will be yielded as the last step of the setup process
client.listen do
  EM.add_timer(0.1) { client.stop_listening }
end
