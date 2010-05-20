# require 'rubygems'
# require 'ruby-debug'
# Debugger.start

module Beetle
  class RedisConfigurationServer
    
    def start
      puts "Starting RedisConfigurationServer" if $DEBUG
      RedisConfigurationClientMessageHandler.delegate_messages_to = self
      beetle_client.listen do
        redis_master_watcher.watch
      end
    end
    
    # Methods called from RedisConfigurationClientMessageHandler
    def client_online(payload)
      puts "Received 'client_online' message" if $DEBUG
      p payload if $DEBUG
    end

    def client_offline(payload)
      puts "Received 'client_offline' message" if $DEBUG
    end
    
    def client_invalidated(payload)
      puts "Received 'client_invalidated' message" if $DEBUG
    end
    
    # Method called from RedisWatcher
    def redis_unavailable(exception)
      puts "Redis master unavailable: #{exception.inspect}" if $DEBUG
      # invalidate_current_master
      # wait_for_invalidation_acknowledgements
      new_redis_master.slaveof("no one")
      p new_redis_master.info
      # beetle_client.publish(:reconfigure, {:host => new_redis_master.host, :port => new_redis_master.port}.to_json)
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
          EventMachine::add_periodic_timer(1) { 
            begin
              @redis.info
            rescue Exception => e
              @watcher_delegate.__send__(:redis_unavailable, e)
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
      
      def first_available_redis_slave
        redis_slaves.find { |redis_slave| redis_slave.info rescue false }
      end
      
      def redis_slaves
        all_redis.select{ |redis| redis.info["role"] == "slave" }
      end
      
      def all_redis
        [6381, 6382].map{ |port| Redis.new(:host => "127.0.0.1", :port => port) }
      end
      
      def get_active_master_from(client_id)
        beetle_client.rpc(:get_active_master, {}.to_json, {:key => client_id})
      end


      # def active_master_reachable?
      #   if active_master
      #     return true if reachable?(active_master)
      #     client.config.redis_configuration_master_retries.times do
      #       sleep client.config.redis_configuration_master_retry_timeout.to_i
      #       return true if reachable?(active_master)
      #     end
      #   end
      #   false
      # end
      # 
      # def find_active_master(force_change = false)
      #   if !force_change && active_master
      #     return if reachable?(active_master)
      #     client.config.redis_configuration_master_retries.times do
      #       sleep client.config.redis_configuration_master_retry_timeout.to_i
      #       return if reachable?(active_master)
      #     end
      #   end
      #   available_redis_server = (client.deduplication_store.redis_instances - [active_master]).sort_by {rand} # randomize redis stores to not return the same one on missed promises
      #   available_redis_server.each do |redis|
      #     reconfigure(redis) and break if reachable?(redis)
      #   end
      # end
      # 
      # def give_master(payload)
      #   # stores our list of servers and their ping times
      #   alive_servers[payload['server_name']] = Time.now # unless vote_in_progess
      #   active_master || 'undefined'
      # end
      # 
      # def reconfigure(new_master)
      #   client.publish(:reconfigure, {:host => new_master.host, :port => new_master.port}.to_json)
      #   setup_reconfigured_check_timer(new_master)
      # end
      # 
      # def going_offline(payload)
      #   alive_servers[payload['sender_name']] = nil
      # end


    end
end