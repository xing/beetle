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
  config.queue   :going_down

  config.message :reconfigure
  config.queue   :reconfigure

  config.message :reconfigured
  config.queue   :reconfigured

  config.message :invalidate
  config.queue   :invalidate

  config.message :invalidated
  config.queue   :invalidated

  config.handler(:online,       Beetle::RedisConfigurationServer)
  config.handler(:going_down,   Beetle::RedisConfigurationServer)
  config.handler(:reconfigured, Beetle::RedisConfigurationServer)
  config.handler(:invalidated,  Beetle::RedisConfigurationServer)

  config.handler(:reconfigure,  Beetle::RedisConfigurationClient)
  config.handler(:invalidate,   Beetle::RedisConfigurationClient)
end

client.publish(:online, {:server_name => 'BAM'}.to_json)

client.listen