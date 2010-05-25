module Beetle
  class RedisConfigurationServer
    include RedisConfigurationLogger
    
    def start
      logger.info "RedisConfigurationServer Starting"
      RedisConfigurationClientMessageHandler.delegate_messages_to = self
      logger.info "Listening and watching"
      beetle_client.listen do
        redis_master_watcher.watch
      end
    end
    
    # Methods called from RedisConfigurationClientMessageHandler
    def client_online(payload)
      id = payload["id"]
      logger.info "Received client_online message from id '#{id}'"
    end

    def client_offline(payload)
      id = payload["id"]
      logger.info "Received client_offline message from id '#{id}'"
    end
    
    def client_invalidated(payload)
      id = payload["id"]
      logger.info "Received client_invalidated message from id '#{id}'"
    end
    
    # Method called from RedisWatcher
    def redis_unavailable
      logger.warn "Redis master not available"
      # invalidate_current_master
      # wait_for_invalidation_acknowledgements
      if new_redis_master
        logger.warn "Setting new redis master to #{new_redis_master.server}"
        host = new_redis_master_host
        port = new_redis_master_port
        new_redis_master.slaveof("no one")
        @redis_master = Redis.new(:host => host, :port => port)
        logger.info "Publishing reconfigure message with host '#{host}' port '#{port}'"
        beetle_client.publish(:reconfigure, {:host => host, :port => port}.to_json)
      else
        logger.error "No redis slave available to become new master"
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
        def initialize(redis, watcher_delegate)
          @redis = redis
          @watcher_delegate = watcher_delegate
        end
        
        def watch
          timer = EventMachine::add_periodic_timer(1) { 
            begin
              @redis.info
            rescue Exception
              @watcher_delegate.__send__(:redis_unavailable)
              timer.cancel
            end
          }
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
          config.message :client_invalidated
          config.queue   :client_invalidated
          config.message :reconfigure
          config.queue   :reconfigure

          config.handler(:client_online,      RedisConfigurationClientMessageHandler)
          config.handler(:client_offline,     RedisConfigurationClientMessageHandler)
          config.handler(:client_invalidated, RedisConfigurationClientMessageHandler)
        end
        beetle_client
      end
      
      def redis_master_watcher
        @redis_master_watcher ||= RedisWatcher.new(redis_master, self)
      end
      
      def redis_master
        @redis_master ||= Redis.new(:host => "127.0.0.1", :port => 6381)
      end
      
      def new_redis_master
        first_available_redis_slave
      end
      
      def new_redis_master_host
        new_redis_master.server.split(":")[0]
      end
      
      def new_redis_master_port
        new_redis_master.server.split(":")[1]
      end
      
      def first_available_redis_slave
        available_redis_slaves.find { |redis_slave| redis_slave.info }
      end
      
      def available_redis_slaves
        all_redis.select{ |redis| redis.info["role"] == "slave" rescue false }
      end
      
      def all_redis
        [6381, 6382].map{ |port| Redis.new(:host => "127.0.0.1", :port => port) }
      end
    end
end