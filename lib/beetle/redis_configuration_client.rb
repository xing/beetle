module Beetle
  class RedisConfigurationClient < Beetle::Handler

    def start
      puts "Starting RedisConfigurationClient" if $DEBUG
      RedisConfigurationServerMessageHandler.delegate_messages_to = self
      beetle_client.publish(:client_online, {:server_name => `hostname`.chomp}.to_json)
      beetle_client.listen
    end

    # RedisConfigurationServerMessageHandler delegated messages
    def invalidate(payload)
      @redis_master = nil
    end

    def reconfigure(payload)
      @redis_master = Redis.new(:host => payload[:host], :port => payload[:port])
      @redis_master.info
    end
    
    private
    
      class RedisConfigurationServerMessageHandler < Beetle::Handler
        cattr_accessor :delegate_messages_to
        def process
          self.class.delegate_messages_to.__send__(message.header.routing_key, ActiveSupport::JSON.decode(message.data))
        end
      end
      
      
      def beetle_client
        @beetle_client ||= build_beetle_client
      end
      
      def build_beetle_client
        beetle_client = Beetle::Client.new
        beetle_client.configure :exchange => :system do |config|
          config.message :client_online
          config.queue   :client_online
          config.message :client_offline
          config.queue   :client_offline
          config.message :invalidate
          config.queue   :invalidate
          config.message :client_invalidated
          config.queue   :client_invalidated
          config.message :reconfigure
          config.queue   :reconfigure

          config.handler(:invalidate,   RedisConfigurationServerMessageHandler)
          config.handler(:reconfigure,  RedisConfigurationServerMessageHandler)
        end
        beetle_client
      end
    
  end
end
