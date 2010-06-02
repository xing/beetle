module Beetle
  class RedisConfigurationServer
    include RedisConfigurationLogger
    
    def initialize
      RedisConfigurationClientMessageHandler.delegate_messages_to = self
      @clients_online = {}
      @client_invalidated_messages_received = {}
    end

    def start
      logger.info "RedisConfigurationServer Starting"
      beetle_client.listen do
        redis_master_watcher.watch
      end
    end

    # Methods called from RedisConfigurationClientMessageHandler
    def client_online(payload)
      id = payload["id"]
      logger.info "Received client_online message from id '#{id}'"
      @clients_online[id] = true
      beetle_client.publish(:reconfigure, {:host => redis_master.host, :port => redis_master.port}.to_json)
    end

    def client_offline(payload)
      id = payload["id"]
      logger.info "Received client_offline message from id '#{id}'"
    end

    def client_invalidated(payload)
      id = payload["id"]
      logger.info "Received client_invalidated message from id '#{id}'"
      @client_invalidated_messages_received[id] = true
      switch_master if all_client_invalidated_messages_received?
    end

    # Method called from RedisWatcher
    def redis_unavailable
      logger.warn "Redis master '#{redis_master.server}' not available"
      if @clients_online.empty?
        switch_master
      else
        invalidate_current_master
      end
    end

    private

    class RedisConfigurationClientMessageHandler < Beetle::Handler
      cattr_accessor :delegate_messages_to
      def process
        method_name = message.header.routing_key
        payload = ActiveSupport::JSON.decode(message.data)
        self.class.delegate_messages_to.__send__(method_name, payload)
      end
    end

    class RedisWatcher
      attr_accessor :redis, :pause

      def initialize(redis, watcher_delegate, logger)
        @redis = redis
        @watcher_delegate = watcher_delegate
        @logger = logger
        @retries = 0
      end

      def watch
        EventMachine::add_periodic_timer(1) {
          if @redis
            @logger.debug "Watching redis '#{@redis.server}'"
            unless @redis.available?
              if (@retries+=1) >= Beetle.config.redis_configuration_master_retries
                @retries = 0
                @watcher_delegate.__send__(:redis_unavailable)
              end
            end
          end
        }
      end
    end

    def beetle_client
      @beetle_client ||= build_beetle_client
    end

    def build_beetle_client
      beetle_client = Beetle::Client.new
      beetle_client.configure :exchange => :system, :auto_delete => true do |config|
        config.message :client_online
        config.queue   :client_online
        config.message :client_offline
        config.queue   :client_offline
        config.message :client_invalidated
        config.queue   :client_invalidated
        config.message :invalidate
        config.message :reconfigure

        config.handler(:client_online,      RedisConfigurationClientMessageHandler)
        config.handler(:client_offline,     RedisConfigurationClientMessageHandler)
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
      all_available_redis.find{ |redis| redis.master? }
    end

    def all_available_redis
      all_redis.select{ |redis| redis.available? }
    end

    def all_redis
      beetle_client.config.redis_hosts.split(",").map do |redis_server_string|
        Redis.from_server_string(redis_server_string)
      end
    end

    def new_redis_master
      @new_redis_master ||= redis_slaves.first
    end

    def redis_slaves
      all_available_redis.select{ |redis| redis.slave? }
    end
    
    def invalidate_current_master
      @client_invalidated_messages_received = {}
      beetle_client.publish(:invalidate, {}.to_json)
    end
    
    def all_client_invalidated_messages_received?
      @clients_online.size == @client_invalidated_messages_received.size
    end
    
    def switch_master
      if new_redis_master
        logger.warn "Setting new redis master to '#{new_redis_master.server}'"
        new_redis_master.master!
        logger.info "Publishing reconfigure message with new host '#{new_redis_master.host}' port '#{new_redis_master.port}'"
        beetle_client.publish(:reconfigure, {:host => new_redis_master.host, :port => new_redis_master.port}.to_json)
        @redis_master = Redis.new(:host => new_redis_master.host, :port => new_redis_master.port)
        @new_redis_master = nil
        
        redis_master_watcher.redis = redis_master
      else
        logger.error "No redis slave available to become new master"
      end
    end

  end
end
