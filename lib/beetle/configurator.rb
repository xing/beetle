require 'timeout'
module Beetle
  class Configurator < Beetle::Handler

    @@active_master     = nil
    @@client            = Beetle::Client.new
    @@alive_signals     = {}
    @@proposal_answers  = {}
    cattr_accessor :client
    cattr_accessor :active_master
    cattr_accessor :alive_signals
    cattr_accessor :proposal_answers

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
        available_redis_server.each do |redis|
          propose(redis) and break if reachable?(redis)
        end
      end

      def give_master(payload)
        # stores our list of servers and their ping times
        # alive_signals[server_name] = Time.now
        active_master || 'undefined'
      end

      def propose(new_master)
        clear_active_master
        client.publish(:propose, {:host => new_master.host, :port => new_master.port}.to_json)
        setup_propose_check_timer
        # 1. wait for every server to respond (they delete the current redis from their config file before (!) they responde; then they check if they can reach it and answer with an ack/deny accordingly)
        # 2. setup new redis master (slaveof(no one))
        # 3. send reconfigure command
        # 4. wait until everyone confirmed the reconfigure
        # 5. set active_master to new master
      end

      def all_promised?

      end

      def reconfigure

      end

      def promise(payload)
        proposal_answers[payload['sender_name']] = payload['acked_server']
      end

      def reconfigured(payload)

      end

      def going_offline(payload)

      end

      private

      def clear_active_master
        self.active_master = nil
      end

      def setup_propose_check_timer
        self.proposal_answers = {}
        EM.add_timer(30) {
          check_propose_answers
        }
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

    def process
      hash = ActiveSupport::JSON.decode(message.data)
      self.class.__send__(hash.delete("op").to_sym, hash)
    end

  end
end