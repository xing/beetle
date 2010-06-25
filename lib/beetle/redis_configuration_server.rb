module Beetle
  class RedisConfigurationServer
    include Logging

    attr_reader :redis_master, :invalidation_message_token

    # redis_server_strings is an array like ["192.168.1.2:6379", "192.168.1.3:6379"]
    def initialize(redis_server_strings = [])
      @redis_server_strings = redis_server_strings
      @client_ids = Beetle.config.redis_configuration_client_ids.split(",")
      @invalidation_message_token = (Time.now.to_f * 1000).to_i
      @client_invalidated_messages_received = {}
      @paused = true
      RedisConfigurationClientMessageHandler.configuration_server = self
    end

    def paused?
      redis_master_watcher.paused?
    end

    def start
      logger.info "RedisConfigurationServer Starting"
      beetle_client.listen do
        redis_master_watcher.watch
      end
    end

    # Method called from RedisConfigurationClientMessageHandler
    def client_invalidated(payload)
      id = payload["id"]
      token = payload["token"]
      logger.info "Received client_invalidated message from id '#{id}' with token '#{token}'"
      if token != @invalidation_message_token
        logger.info "Ignored client_invalidated message from id '#{id}' (token was '#{token}', but expected '#{@invalidation_message_token}')"
        return
      end
      @client_invalidated_messages_received[id] = true
      if all_client_invalidated_messages_received?
          @invalidate_timer.cancel if @invalidate_timer
          switch_master
      end
    end

    # Method called from RedisWatcher
    def redis_unavailable
      msg = "Redis master '#{redis_master.server}' not available"
      redis_master_watcher.pause
      logger.warn(msg)
      beetle_client.publish(:system_notification, {"message" => msg}.to_json)

      if @client_ids.empty?
        switch_master
      else
        invalidate_current_master
      end
    end

    private

    def beetle_client
      @beetle_client ||= build_beetle_client
    end

    def build_beetle_client
      beetle_client = Beetle::Client.new
      beetle_client.configure :exchange => :system, :auto_delete => true do |config|
        config.message :client_invalidated
        config.queue   :client_invalidated
        config.message :invalidate
        config.message :reconfigure
        config.message :system_notification

        config.handler(:client_invalidated, RedisConfigurationClientMessageHandler)
      end
      beetle_client
    end

    def redis_master_watcher
      @redis_master_watcher ||= RedisWatcher.new(redis_master, self, logger)
    end

    def redis_master
      @redis_master ||= initial_redis_master
    end

    def initial_redis_master
      # TODO retry if nil
      all_available_redis.find{|redis| redis.master? }
    end

    def all_available_redis
      all_redis.select{|redis| redis.available? }
    end

    def all_redis
      @all_redis ||= @redis_server_strings.map{|r| Redis.from_server_string(r) }
    end

    def new_redis_master
      @new_redis_master ||= redis_slaves.first
    end

    def redis_slaves
      all_available_redis.select{|redis| redis.slave_of?(redis_master.host, redis_master.port) }
    end

    def invalidate_current_master
      generate_new_token
      @client_invalidated_messages_received = {}
      beetle_client.publish(:invalidate, {"token" => @invalidation_message_token}.to_json)
      @invalidate_timer = EM::Timer.new(Beetle.config.redis_configuration_master_invalidation_timeout) do
        generate_new_token
        redis_master_watcher.continue
      end
    end

    def generate_new_token
      @invalidation_message_token += 1
    end

    def all_client_invalidated_messages_received?
      Set.new(@client_ids) == Set.new(@client_invalidated_messages_received.keys)
    end

    def switch_master
      if new_redis_master
        msg = "Redis master switched from '#{@redis_master.server}' to '#{new_redis_master.server}'"
        logger.warn(msg)
        beetle_client.publish(:system_notification, {"message" => msg}.to_json)

        new_redis_master.master!
        logger.info "Publishing reconfigure message with new host '#{new_redis_master.host}' port '#{new_redis_master.port}'"
        beetle_client.publish(:reconfigure, {:host => new_redis_master.host, :port => new_redis_master.port}.to_json)
        @redis_master = Redis.new(:host => new_redis_master.host, :port => new_redis_master.port)
        @new_redis_master = nil

        redis_master_watcher.redis = redis_master
      else
        msg = "Redis master could not be switched, no slave available to become new master"
        logger.error(msg)
        beetle_client.publish(:system_notification, {"message" => msg}.to_json)
      end
      redis_master_watcher.continue
    end
    
    class RedisConfigurationClientMessageHandler < Beetle::Handler
      cattr_accessor :configuration_server

      delegate :client_invalidated, :to => :@@configuration_server

      def process
        method_name = message.header.routing_key
        payload = ActiveSupport::JSON.decode(message.data)
        send(method_name, payload)
      end
    end

    class RedisWatcher
      attr_accessor :redis

      def initialize(redis, configuration_server, logger)
        @redis = redis
        @configuration_server = configuration_server
        @logger = logger
        @retries = 0
      end

      def pause
        @watch_timer.cancel if @watch_timer
        @paused = true
      end

      def watch
        @watch_timer ||= EventMachine::add_periodic_timer(Beetle.config.redis_configuration_master_retry_timeout) {
          if @redis
            @logger.debug "Watching redis '#{@redis.server}'"
            unless @redis.available?
              if (@retries+=1) >= Beetle.config.redis_configuration_master_retries
                @retries = 0
                @configuration_server.redis_unavailable
              end
            end
          end
        }
        @paused = false
      end
      alias continue watch

      def paused?
        @paused
      end
    end
  end
end
