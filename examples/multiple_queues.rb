# A simple usage example for Beetle
require "rubygems"
require File.expand_path(File.dirname(__FILE__)+"/../lib/beetle")

# suppress debug messages
Beetle.config.logger.level = Logger::INFO

# instantiate a client
client = Beetle::Client.new

client.configure :exchange => :foobar, :key => "foobar" do |config|
  config.queue :queue_1
  config.queue :queue_2
  config.message :foobar
  config.handler(:queue_1) { puts "Queue 1" }
  config.handler(:queue_2) { puts "Queue 2" }
end

client.publish(:foobar, "baz")

client.listen do
  EM.add_timer(0.1) { client.stop_listening }
end

