module Beetle
  # A RedisConfigurationServer is the supervisor part of beetle's
  # redis failover solution
  #
  # An single instance of RedisConfigurationServer works as a supervisor for
  # several RedisConfigurationClient instances. It is responsible for watching
  # the redis master and electing and publishing a new master in case of failure.
  #
  # It will make sure that all configured RedisConfigurationClient instances
  # do not use the old master anymore before making a switch, to prevent
  # inconsistent data.
  #
  # Usually started via <tt>beetle configuration_server</tt> command.
  class RedisConfigurationServer
    include Logging
    include RedisConfigurationAutoDetection
    include RedisMasterFile

    # The current redis master
    attr_reader :redis_master

    # The current token used to detect correct message order
    attr_reader :current_token

    # Redis servers by role
    attr_reader :redis_servers

    # redis_server_strings is an array of host:port strings,
    # e.g. ["192.168.1.2:6379", "192.168.1.3:6379"]
    #
    # Exactly one of them must be a redis master.
    def initialize(redis_server_strings = [])
      @redis_server_strings = redis_server_strings
      @client_ids = Set.new(beetle_client.config.redis_configuration_client_ids.split(","))
      @current_token = (Time.now.to_f * 1000).to_i
      @client_pong_ids_received = Set.new
      @client_invalidated_ids_received = Set.new
      update_redis_server_info
      RedisConfigurationClientMessageHandler.configuration_server = self
    end

    # Test if redis is currently being watched
    def paused?
      redis_master_watcher.paused?
    end

    # Start watching redis
    def start
      logger.info "RedisConfigurationServer Starting"
      logger.info "Redis servers : #{@redis_server_strings.join(',')}"
      logger.info "AMQP servers  : #{beetle_client.config.servers}"
      logger.info "Client ids    : #{beetle_client.config.redis_configuration_client_ids}"
      beetle_client.listen do
        redis_master_watcher.watch
      end
    end

    # Method called from RedisConfigurationClientMessageHandler
    # when "pong" message from a RedisConfigurationClient is received
    def pong(payload)
      id = payload["id"]
      token = payload["token"]
      logger.info "Received pong message from id '#{id}' with token '#{token}'"
      return unless redeem_token(token)
      @client_pong_ids_received << id
      if all_client_pong_ids_received?
        logger.debug "All client pong messages received"
        @available_timer.cancel if @available_timer
        invalidate_current_master
      end
    end

    # Method called from RedisConfigurationClientMessageHandler
    # when "client_invalidated" message from a RedisConfigurationClient is received
    def client_invalidated(payload)
      id = payload["id"]
      token = payload["token"]
      logger.info "Received client_invalidated message from id '#{id}' with token '#{token}'"
      return unless redeem_token(token)
      @client_invalidated_ids_received << id
      if all_client_invalidated_ids_received?
        logger.debug "All client invalidated messages received"
        @invalidate_timer.cancel if @invalidate_timer
        switch_master
      end
    end

    # Method called from RedisWatcher when watched redis becomes unavailable
    def master_unavailable
      msg = "Redis master '#{redis_master.server}' not available (#{@redis_server_info.inspect})"
      redis_master_watcher.pause
      logger.warn(msg)
      beetle_client.publish(:system_notification, {"message" => msg}.to_json)

      if @client_ids.empty?
        switch_master
      else
        start_invalidation
      end
    end

    # Method called from RedisWatcher when watched redis is available
    def master_available
      publish_master(redis_master)
      configure_slaves(redis_master)
    end

    def master_available?
      @redis_server_info["master"].include?(redis_master)
    end
    
    def update_redis_server_info
      logger.debug "Updating redis server info"
      @redis_server_info = Hash.new {|h,k| h[k]= []}
      redis_instances.each {|r| @redis_server_info[r.role] << r}
    end

    private

    def beetle_client
      @beetle_client ||= build_beetle_client
    end

    def build_beetle_client
      Beetle::Client.new.configure :exchange => :system, :auto_delete => true do |config|
        config.message :client_invalidated
        config.queue   :client_invalidated
        config.message :pong
        config.queue   :pong
        config.message :ping
        config.message :invalidate
        config.message :reconfigure
        config.message :system_notification

        config.handler(:pong,               RedisConfigurationClientMessageHandler)
        config.handler(:client_invalidated, RedisConfigurationClientMessageHandler)
      end
    end

    def redis_master_watcher
      @redis_master_watcher ||= RedisWatcher.new(self)
    end

    def redis_master
      # TODO what to do if auto-detection failed?
      @redis_master ||= determine_initial_redis_master
    end

    def determine_initial_redis_master
      auto_detect_master || redis_master_from_master_file
    end

    def redis_instances
      @redis_instances ||= @redis_server_strings.map{|r| Redis.from_server_string(r, :timeout => 3) }
    end

    def detect_new_redis_master
      redis_slaves_of_master.first
    end

    def redis_slaves_of_master
      @redis_server_info["slave"].select{|r| r.slave_of?(redis_master.host, redis_master.port)}
    end

    def other_redis_masters(master)
      @redis_server_info["master"].reject{|r| r.server == master.server}
    end

    def redeem_token(token)
      valid_token = token == @current_token
      logger.info "Ignored message (token was '#{token.inspect}', but expected '#{@current_token.inspect}')" unless valid_token
      valid_token
    end

    def start_invalidation
      @client_pong_ids_received.clear
      @client_invalidated_ids_received.clear
      check_all_clients_available
    end

    def check_all_clients_available
      generate_new_token
      beetle_client.publish(:ping, {"token" => @current_token}.to_json)
      @available_timer = EM::Timer.new(beetle_client.config.redis_configuration_client_timeout) { cancel_invalidation }
    end

    def invalidate_current_master
      generate_new_token
      beetle_client.publish(:invalidate, {"token" => @current_token}.to_json)
      @invalidate_timer = EM::Timer.new(beetle_client.config.redis_configuration_client_timeout) { cancel_invalidation }
    end

    def cancel_invalidation
      logger.warn "Redis master invalidation cancelled: 'pong' received from '#{@client_pong_ids_received.to_a.join(',')}', 'client_invalidated' received from '#{@client_invalidated_ids_received.to_a.join(',')}'"
      generate_new_token
      redis_master_watcher.continue
    end

    def generate_new_token
      @current_token += 1
    end

    def all_client_pong_ids_received?
      @client_ids == @client_pong_ids_received
    end

    def all_client_invalidated_ids_received?
      @client_ids == @client_invalidated_ids_received
    end

    def switch_master
      if new_redis_master = detect_new_redis_master
        new_redis_master.master!
        publish_master(new_redis_master)

        msg = "Redis master switched from '#{@redis_master.server}' to '#{new_redis_master.server}'"
        logger.warn(msg)
        beetle_client.publish(:system_notification, {"message" => msg}.to_json)

        @redis_master = new_redis_master
      else
        msg = "Redis master could not be switched, no slave available to become new master, promoting old master"
        logger.error(msg)
        beetle_client.publish(:system_notification, {"message" => msg}.to_json)
        publish_master(redis_master)
      end
      redis_master_watcher.continue
    end

    def publish_master(master)
      logger.info "Publishing reconfigure message with server '#{master.server}'"
      beetle_client.publish(:reconfigure, {:server => master.server}.to_json)
    end

    def configure_slaves(master)
      other_redis_masters(master).each do |r|
        logger.info "Reconfiguring '#{r.server}' as a slave of '#{master.server}'"
        r.slave_of!(master.host, master.port)
      end
    end

    class RedisConfigurationClientMessageHandler < Beetle::Handler
      cattr_accessor :configuration_server

      delegate :pong, :client_invalidated, :to => :@@configuration_server

      def process
        method_name = message.header.routing_key
        payload = ActiveSupport::JSON.decode(message.data)
        send(method_name, payload)
      end
    end

    class RedisWatcher #:nodoc:
      include Logging

      def initialize(configuration_server)
        @configuration_server = configuration_server
        @retries = 0
        @paused = true
        beetle_client = configuration_server.__send__(:beetle_client)
        @master_retry_timeout = beetle_client.config.redis_configuration_master_retry_timeout
        @master_retries = beetle_client.config.redis_configuration_master_retries
      end

      def pause
        logger.info "Pause checking availability of redis servers"
        @watch_timer.cancel if @watch_timer
        @watch_timer = nil
        @paused = true
      end

      def watch
        @watch_timer ||=
          begin
            logger.info "Start watching redis servers every #{@master_retry_timeout} seconds"
            EventMachine::add_periodic_timer(@master_retry_timeout) { check_availability }
          end
        @paused = false
      end
      alias continue watch

      def paused?
        @paused
      end

      private
      def check_availability
        @configuration_server.update_redis_server_info
        if @configuration_server.master_available?
          @configuration_server.master_available
        else
          logger.warn "Redis master not available! (Retries left: #{@master_retries - (@retries + 1)})"
          if (@retries+=1) >= @master_retries
            @retries = 0
            @configuration_server.master_unavailable
          end
        end
      end

    end
  end
end
