require 'timeout'
module Beetle
  class RedisConfigurationClient < Beetle::Handler

    class SystemMessageHandler < Beetle::Handler
      cattr_accessor :delegate_messages_to
      def process
        self.class.delegate_messages_to.__send__(message.header.routing_key, ActiveSupport::JSON.decode(message.data))
      end
    end
    
    attr_accessor :active_master
    
    def initialize
      SystemMessageHandler.delegate_messages_to = self

      @beetle_client = Beetle::Client.new
      @beetle_client.configure :exchange => :system do |config|
        config.message :online
        config.queue   :online
        config.message :going_down
        config.queue   :going_down
        config.message :reconfigure
        config.queue   :reconfigure
        config.message :invalidate
        config.queue   :invalidate
        config.message :invalidated
        config.queue   :invalidated
        config.handler(:reconfigure,  SystemMessageHandler)
        config.handler(:invalidate,   SystemMessageHandler)
      end
    end
    
    def start
      @beetle_client.listen
    end

    # SystemMessageHandler delegated messages
    def reconfigure(payload)
      
    end
    
    def invalidate(payload)
      
    end

    private
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
