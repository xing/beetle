# require 'rubygems'
# require 'ruby-debug'
# Debugger.start

require 'timeout'
module Beetle
  class RedisConfigurationServer
    
    class SystemMessageHandler < Beetle::Handler
      cattr_accessor :delegate_messages_to
      def process
        self.class.delegate_messages_to.__send__(message.header.routing_key, ActiveSupport::JSON.decode(message.data))
      end
    end
    
    attr_accessor :active_master
    attr_accessor :alive_servers
    
    def initialize
      SystemMessageHandler.delegate_messages_to = self

      @beetle_client = Beetle::Client.new
      @beetle_client.configure :exchange => :system do |config|
        config.message :online
        config.queue   :online
        config.message :going_down
        config.queue   :going_down
        config.message :invalidated
        config.queue   :invalidated

        config.handler(:online,       SystemMessageHandler)
        config.handler(:going_down,   SystemMessageHandler)
        config.handler(:invalidated,  SystemMessageHandler)
      end
      self.alive_servers = {}
    end
    
    def start
      # do other stuff too
      @beetle_client.listen
    end
    
    # SystemMessageHandler delegated messages
    def online(payload)
      alive_servers[payload['server_name']] = Time.now # unless vote_in_progess
      p alive_servers
    end

    def going_down(payload)
    end
    
    def invalidated(payload)
    end
    
    private

      def active_master_reachable?
        if active_master
          return true if reachable?(active_master)
          client.config.redis_configuration_master_retries.times do
            sleep client.config.redis_configuration_master_retry_timeout.to_i
            return true if reachable?(active_master)
          end
        end
        false
      end

      def find_active_master(force_change = false)
        if !force_change && active_master
          return if reachable?(active_master)
          client.config.redis_configuration_master_retries.times do
            sleep client.config.redis_configuration_master_retry_timeout.to_i
            return if reachable?(active_master)
          end
        end
        available_redis_server = (client.deduplication_store.redis_instances - [active_master]).sort_by {rand} # randomize redis stores to not return the same one on missed promises
        available_redis_server.each do |redis|
          reconfigure(redis) and break if reachable?(redis)
        end
      end

      def give_master(payload)
        # stores our list of servers and their ping times
        alive_servers[payload['server_name']] = Time.now # unless vote_in_progess
        active_master || 'undefined'
      end

      def reconfigure(new_master)
        client.publish(:reconfigure, {:host => new_master.host, :port => new_master.port}.to_json)
        setup_reconfigured_check_timer(new_master)
      end

      def going_offline(payload)
        alive_servers[payload['sender_name']] = nil
      end

      def server_alive?(server)
        alive_servers[server] && (alive_servers[server] > Time.now - 10.seconds)
      end

      def switch_master(new_master)
        new_master.slaveof('NO ONE')
        active_master = new_master
      end

      def reset
        self.alive_servers = {}
        self.active_master = {}
      end

      private
      def clear_active_master
        self.active_master = nil
      end

      def setup_reconfigured_check_timer(new_master)
        EM.add_timer(client.config.redis_configuration_reconfiguration_timeout.to_i) do 
          check_reconfigured_answers(new_master)
        end
      end

      def check_reconfigured_answers(new_master)
        if all_alive_servers_reconfigured?(new_master)
          switch_master(new_master)
        else
          setup_reconfigured_check_timer(new_master)
        end
      end

      def all_alive_servers_reconfigured?(new_master)
        reconfigured_answers.all? {|k,v| v == new_master.server}
      end

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