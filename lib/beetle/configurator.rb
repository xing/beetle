require 'timeout'
module Beetle
  class Configurator < Beetle::Handler

    @@active_master  = nil
    @@client         = Beetle::Client.new
    @@alive_signals  = {}
    cattr_accessor :client
    cattr_accessor :active_master
    cattr_accessor :alive_signals

    class << self
      def find_active_master
        if active_master
          return if reachable?(active_master)
          client.config.redis_watcher_retries.times do
            sleep client.config.redis_watcher_retry_timeout.to_i
            return if reachable?(active_master)
          end
        end
        available_redis_server = client.deduplication_store.redis_instances - [active_master]
        self.active_master = nil
        available_redis_server.each do |redis|
          if reachable?(redis)
            self.active_master = redis
          end
        end
      end

      def give_master(payload)
        # stores our list of servers and their ping times
        # alive_signals[server_name] = Time.now
        active_master || 'undefined'
      end

      def propose(new_master)
        client.publish(:propose, new_master)
        self.active_master = nil
      end

      def promise(payload)

      end

      def reconfigured(payload)

      end

      def going_offline(payload)

      end

      private

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

    def process
      hash = ActiveSupport::JSON.decode(message.data)
      self.class.__send__(hash.delete("op").to_sym, hash)
    end

  end
end