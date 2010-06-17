module Beetle
  class RedisConfigurationClient < Beetle::Handler
    include RedisConfigurationLogger

    attr_writer :id

    def id
      @id || `hostname`.chomp
    end

    # redis_server_strings is an array like ["192.168.1.2:6379", "192.168.1.3:6379"]
    def initialize(redis_server_strings)
      @redis_server_strings = redis_server_strings
      RedisConfigurationServerMessageHandler.delegate_messages_to = self
    end

    def start
      logger.info "RedisConfigurationClient Starting"
      clear_redis_master_file
      auto_configure
      write_redis_master_file(@redis_master.server) if @redis_master
      logger.info "Listening"
      beetle_client.listen
    end

    # Methods called from RedisConfigurationServerMessageHandler
    def invalidate(payload)
      logger.info "Received invalidate message"
      token = payload["token"]
      clear_redis_master_file
      @redis_master = nil
      beetle_client.publish(:client_invalidated, {"id" => id, "token" => token}.to_json)
    end

    def reconfigure(payload)
      host = payload["host"]
      port = payload["port"]
      logger.warn "Received reconfigure message with host '#{host}' port '#{port}'"
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

    def clear_redis_master_file
      logger.debug "Clearing redis master file '#{master_file}'"
      write_redis_master_file("")
    end

    def write_redis_master_file(redis_server_string)
      logger.debug "Writing '#{redis_server_string}' to redis master file '#{master_file}'"
      File.open(master_file, "w"){|f| f.puts redis_server_string}
    end

    def master_file
      Beetle.config.redis_server
    end

    # auto configure redis master
    def auto_configure
      if single_master_reachable? || master_and_slave_reachable?
        @redis_master = redis_instances.find{|r| r.role == "master"}
      end
    end

    # whether we have a master slave configuration
    def single_master_reachable?
      redis_instances.size == 1 && redis_instances.first.master?
    end

    # can we access both master and slave
    def master_and_slave_reachable?
      redis_instances.map(&:role).sort == %w(master slave)
    end

    def redis_instances
      @redis_instances ||= @redis_server_strings.map{|s| Redis.from_server_string(s)}
    end
  end
end
