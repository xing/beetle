module Beetle
  class RedisConfigurationClient < Beetle::Handler
    include RedisConfigurationLogger
    
    attr_accessor :id
    
    def id
      @id || `hostname`.chomp
    end
    
    def start
      logger.info "RedisConfigurationClient Starting"
      RedisConfigurationServerMessageHandler.delegate_messages_to = self
      logger.info "Publishing client_online message with id '#{id}'"
      beetle_client.publish(:client_online, {:id => id}.to_json)
      logger.info "Listening"
      beetle_client.listen
    end

    # Methods called from RedisConfigurationServerMessageHandler
    def invalidate(payload)
      logger.info "Received invalidate message"
      @redis_master = nil
    end

    def reconfigure(payload)
      host = payload["host"]
      port = payload["port"]
      logger.warn "Received reconfigure message with host '#{host}' port '#{port}'"
      logger.warn "Writing redis master info to file #{redis_master_file_path}"
      write_redis_master_file(host, port)
      @redis_master = Redis.new(:host => host, :port => port)
    end
    
    private
    
      class RedisConfigurationServerMessageHandler < Beetle::Handler
        cattr_accessor :delegate_messages_to
        def process
          self.class.delegate_messages_to.__send__(message.header.routing_key, ActiveSupport::JSON.decode(message.data))
        end
      end
      
      def server_name
        `hostname`.chomp
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
          config.queue   internal_queue_name(:invalidate), :key => "invalidate"
          config.message :client_invalidated
          config.queue   :client_invalidated
          config.message :reconfigure
          config.queue   internal_queue_name(:reconfigure), :key => "reconfigure"

          config.handler(internal_queue_name(:invalidate),   RedisConfigurationServerMessageHandler)
          config.handler(internal_queue_name(:reconfigure),  RedisConfigurationServerMessageHandler)
        end
        beetle_client
      end
      
      def internal_queue_name(prefix)
        "#{prefix}-#{id}"
      end
      
      def write_redis_master_file(host, port)
        File.open(redis_master_file_path, "w") do |file|
          file.puts "#{host}:#{port}"
        end
      end
      
      def redis_master_file_path
        beetle_client.config.redis_master_file_path
      end
  end
end
