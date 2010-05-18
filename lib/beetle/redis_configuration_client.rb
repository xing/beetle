require 'timeout'
module Beetle
  class RedisConfigurationClient < Beetle::Handler

    @@active_master         = nil
    @@client                = Beetle::Client.new
    cattr_accessor :active_master
    cattr_accessor :client
    
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
    

    class << self
      def find_active_server(master, slave)
        client.publish(:online, {:server_name => `hostname`}.to_json)
        # client.config.redis_configuration_master_retries.times do
        #   sleep client.config.redis_configuration_master_retry_timeout.to_i
        #   # 
        # end
      end

      def is_valid_master(redis)
        redis.info[:a]
      end

      def is_valid_slave(redis)
        redis.info[:b]
      end

      # DUP
      def reachable?(redis)
        begin
          Timeout::timeout(5) {
            !!redis.info
          }
        rescue Timeout::Error => e
          false
        end
      end

    end
  end
end
