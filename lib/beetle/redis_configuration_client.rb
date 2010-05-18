require 'timeout'
module Beetle
  class RedisConfigurationClient < Beetle::Handler

    class << self
      attr_accessor :active_master
      attr_accessor :beetle_client

      @beetle_client = Beetle::Client.new
      @beetle_client.configure :exchange => :system do |config|
        config.message :online
        config.message :going_down
        config.queue   :reconfigure
        config.message :reconfigured
        config.queue   :invalidate
        config.message :invalidated
        config.handler(:reconfigure,  self)
        config.handler(:invalidate,   self)
      end

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
