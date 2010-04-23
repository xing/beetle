require 'timeout'
module Beetle
  class Configurator < Beetle::Handler

    @@active_master     = nil
    @@client            = Beetle::Client.new
    @@alive_servers     = {}
    @@proposal_answers  = {}
    cattr_accessor :client
    cattr_accessor :active_master
    cattr_accessor :alive_servers
    cattr_accessor :proposal_answers

    class << self
      private :proposal_answers

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
        alive_servers[payload['server_name']] = Time.now
        active_master || 'undefined'
      end

      def propose(new_master)
        setup_proposal_answers
        clear_active_master
        client.publish(:propose, {:host => new_master.host, :port => new_master.port}.to_json)
        setup_propose_check_timer(new_master)
        # 1. wait for every server to respond (they delete the current redis from their config file before (!) they responde; then they check if they can reach it and answer with an ack/deny accordingly)
        # 2. setup new redis master (slaveof(no one))
        # 3. send reconfigure command
        # 4. wait until everyone confirmed the reconfigure
        # 5. set active_master to new master
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

      def server_alive?(server)
        alive_servers[server] && (alive_servers[server] > Time.now - 10.seconds)
      end

      def reset
        self.alive_servers = {}
        self.proposal_answers = {}
        self.active_master = {}
      end

      private
      def setup_proposal_answers
        @@proposal_answers = {}
        alive_servers.each do |alive_signal|
          @@proposal_answers[alive_signal[0]] = nil
        end
      end

      def clear_active_master
        self.active_master = nil
      end

      def setup_propose_check_timer(proposed_server)
        EM.add_timer(client.config.redis_watcher_propose_timer.to_i) {
          check_propose_answers(proposed_server)
        }
      end

      def check_propose_answers(proposed_server)
        if all_alive_servers_promised?(proposed_server)
          reconfigure!(proposed_server)
        else
          setup_propose_check_timer(proposed_server)
        end
      end

      def all_alive_servers_promised?(proposed_server)
        proposal_answers.all? {|k, v| v == proposed_server.server}
      end

      def reconfigure!(new_master)

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