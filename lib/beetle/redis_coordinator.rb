require 'timeout'
module Beetle
  # The authority for the redis master-slave setup.
  class RedisCoordinator < Beetle::Handler

    @@active_master         = nil
    @@client                = Beetle::Client.new
    @@alive_servers         = {}
    @@proposal_answers      = {}
    @@reconfigured_answers  = {}
    cattr_accessor :client
    cattr_accessor :active_master
    cattr_accessor :alive_servers
    cattr_accessor :proposal_answers
    cattr_accessor :reconfigured_answers

    class << self
      private :proposal_answers

      def find_active_master(force_change = false)
        if !force_change && active_master
          return if reachable?(active_master)
          client.config.redis_watcher_retries.times do
            sleep client.config.redis_watcher_retry_timeout.to_i
            return if reachable?(active_master)
          end
        end
        available_redis_server = (client.deduplication_store.redis_instances - [active_master]).sort_by {rand} # randomize redis stores to not return the same one on missed promises
        available_redis_server.each do |redis|
          propose(redis) and break if reachable?(redis)
        end
      end

      def give_master(payload)
        # stores our list of servers and their ping times
        alive_servers[payload['server_name']] = Time.now # unless vote_in_progess
        active_master || 'undefined'
      end

      def propose(new_master)
        setup_proposal_answers
        clear_active_master
        client.publish(:propose, {:host => new_master.host, :port => new_master.port}.to_json)
        setup_propose_check_timer(new_master)
        # 1. wait for every server to respond (they delete the current redis from their config file before (!) they responde; then they check if they can reach it and answer with an 
      end

      def reconfigure(new_master)
        client.publish(:reconfigure, {:host => new_master.host, :port => new_master.port}.to_json)
        setup_reconfigured_check_timer(new_master)
      end

      def promise(payload)
        proposal_answers[payload['sender_name']] = payload['acked_server']
      end

      def reconfigured(payload)
        reconfigured_answers[payload['sender_name']] = payload['acked_server']
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
        EM.add_timer(client.config.redis_watcher_propose_timer.to_i) do
          check_propose_answers(proposed_server)
        end
      end

      def check_propose_answers(proposed_server)
        if all_alive_servers_promised?(proposed_server)
          reconfigure(proposed_server)
        else
          setup_propose_check_timer(proposed_server)
        end
      end

      def all_alive_servers_promised?(proposed_server)
        proposal_answers.all? {|k, v| v == proposed_server.server}
      end

      def setup_reconfigured_check_timer(new_master)
        EM.add_timer(client.config.redis_watcher_propose_timer.to_i) do 
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

    def process
      hash = ActiveSupport::JSON.decode(message.data)
      self.class.__send__(hash.delete("op").to_sym, hash)
    end

  end
end