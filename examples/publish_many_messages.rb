# publish_many_messages.rb
# this script pbulishes ARGV[0] small test messages (or 100000 if no argument is provided)
#
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# start it with ruby publish_many_messages.rb 1000000

require "rubygems"
require File.expand_path("../lib/beetle", File.dirname(__FILE__))

# set Beetle log level to info, less noisy than debug
Beetle.config.logger.level = Logger::INFO

# setup client
client = Beetle::Client.new
client.register_queue(:test)
client.register_message(:test)

# publish a lot of identical messages
n = (ARGV[0] || 100000).to_i
n.times{ client.publish(:test, 'x') }

puts "published #{n} messages"
