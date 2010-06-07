module Beetle
  class RedisConfigurationClient < Beetle::Handler
    include RedisConfigurationLogger

    attr_writer :id

    def id
      @id || `hostname`.chomp
    end

    def initialize
      RedisConfigurationServerMessageHandler.delegate_messages_to = self
    end

    def start
      logger.info "RedisConfigurationClient Starting"
      beetle_client.deduplication_store.auto_configure
      beetle_client.deduplication_store.save_configured_master
      @redis_master = beetle_client.deduplication_store.redis

      logger.info "Listening"
      beetle_client.listen
    end

    # Methods called from RedisConfigurationServerMessageHandler
    def invalidate(payload)
      logger.info "Received invalidate message"
      clear_redis_master_file
      @redis_master = nil
      beetle_client.publish(:client_invalidated, {:id => id}.to_json)
    end

    def reconfigure(payload)
      host = payload["host"]
      port = payload["port"]
      logger.warn "Received reconfigure message with host '#{host}' port '#{port}'"
      logger.warn "Writing redis master info to file '#{beetle_client.deduplication_store.master_file}'"
      write_redis_master_file("#{host}:#{port}")
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
      beetle_client.configure :exchange => :system, :auto_delete => true do |config|
        config.message :invalidate
        config.queue   internal_queue_name(:invalidate), :key => "invalidate"
        config.message :client_invalidated
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

    def write_redis_master_file(server)
      beetle_client.deduplication_store.write_master_file(server)
    end

    def clear_redis_master_file
      write_redis_master_file("")
    end
  end
end
