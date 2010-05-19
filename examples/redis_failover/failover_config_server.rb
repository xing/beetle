# failover_config_client.rb
#  
# 
# 
# 
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# start it with ruby failover_config_client.rb

require "rubygems"
require File.expand_path(File.dirname(__FILE__)+"/../../lib/beetle")

Beetle.config.redis_hosts = "localhost:6379, localhost:6380"
Beetle.config.servers = "localhost:5672, localhost:5673"

# set Beetle log level to info, less noisy than debug
Beetle.config.logger.level = Logger::INFO

# setup client
client = Beetle::Client.new

client.configure :exchange => :system do |config|
  config.message :online
  config.queue   :online
  config.message :going_down
  config.message :invalidated
end

client.publish(:online,{:server_name => `hostname`}.to_json)

Beetle::RedisConfigurationServer.new.start