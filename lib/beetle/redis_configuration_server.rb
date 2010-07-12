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
    include RedisMasterFile

    # The current redis master
    attr_reader :current_master

    # The current token used to detect correct message order
    attr_reader :current_token

    def initialize
      @client_ids = Set.new(config.redis_configuration_client_ids.split(","))
      @current_token = (Time.now.to_f * 1000).to_i
      @client_pong_ids_received = Set.new
      @client_invalidated_ids_received = Set.new
      MessageDispatcher.configuration_server = self
    end

    # Redis system status information
    def redis
      @redis ||= RedisServerInfo.new(config, :timeout => 3)
    end

    def beetle
      @beetle ||= build_beetle
    end

    def config
      beetle.config
    end

    # Start watching redis
    def start
      verify_redis_master_file_string
      check_redis_configuration
      redis.refresh
      determine_initial_master
      log_start
      beetle.listen do
        master_watcher.watch
      end
    end

    # Test if redis is currently being watched
    def paused?
      master_watcher.paused?
    end

    # called by the message dispatcher when a "pong" message from a RedisConfigurationClient is received
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

    # called by the message dispatcher when a "client_invalidated" message from a RedisConfigurationClient is received
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

    # called from RedisWatcher when watched redis becomes unavailable
    def master_unavailable!
      msg = "Redis master '#{current_master.server}' not available"
      master_watcher.pause
      logger.warn(msg)
      beetle.publish(:system_notification, {"message" => msg}.to_json)

      if @client_ids.empty?
        switch_master
      else
        start_invalidation
      end
    end

    # called from RedisWatcher when watched redis is available
    def master_available!
      publish_master(current_master)
      configure_slaves(current_master)
    end

    def master_available?
      redis.masters.include?(current_master)
    end

    private

    def check_redis_configuration
      raise ConfigurationError.new("Redis failover needs two or more redis servers") if redis.instances.size < 2
    end

    def log_start
      logger.info "RedisConfigurationServer starting"
      logger.info "AMQP servers  : #{config.servers}"
      logger.info "Client ids    : #{config.redis_configuration_client_ids}"
      logger.info "Redis servers : #{config.redis_servers}"
      logger.info "Redis master  : #{current_master.server}"
    end

    def build_beetle
      Beetle::Client.new.configure :exchange => :system, :auto_delete => true do |config|
        config.message :client_invalidated
        config.queue   :client_invalidated
        config.message :pong
        config.queue   :pong
        config.message :ping
        config.message :invalidate
        config.message :reconfigure
        config.message :system_notification

        config.handler(:pong,               MessageDispatcher)
        config.handler(:client_invalidated, MessageDispatcher)
      end
    end

    class MessageDispatcher < Beetle::Handler
      cattr_accessor :configuration_server
      def process
        @@configuration_server.__send__(message.header.routing_key, ActiveSupport::JSON.decode(message.data))
      end
    end

    def master_watcher
      @master_watcher ||= RedisWatcher.new(self)
    end

    def determine_initial_master
      if master_file_exists? && @current_master = redis_master_from_master_file
        if redis.slaves.include?(current_master)
          master_unavailable!
        elsif redis.unknowns.include?(current_master)
          master_unavailable!
        elsif redis.unknowns.size == redis.instances.size
          raise NoRedisMaster.new("failed to determine initial redis master")
        end
      else
        write_redis_master_file(current_master.server) if @current_master = redis.auto_detect_master
      end
      current_master or raise NoRedisMaster.new("failed to determine initial redis master")
    end

    def detect_new_master
      redis.unknowns.include?(current_master) ? redis.slaves_of(current_master).first : current_master
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
      beetle.publish(:ping, payload_with_current_token)
      @available_timer = EM::Timer.new(config.redis_configuration_client_timeout) { cancel_invalidation }
    end

    def invalidate_current_master
      generate_new_token
      beetle.publish(:invalidate, payload_with_current_token)
      @invalidate_timer = EM::Timer.new(config.redis_configuration_client_timeout) { cancel_invalidation }
    end

    def cancel_invalidation
      logger.warn "Redis master invalidation cancelled: 'pong' received from '#{@client_pong_ids_received.to_a.join(',')}', 'client_invalidated' received from '#{@client_invalidated_ids_received.to_a.join(',')}'"
      generate_new_token
      master_watcher.continue
    end

    def generate_new_token
      @current_token += 1
    end

    def payload_with_current_token(message = {})
      message["token"] = @current_token
      message.to_json
    end

    def all_client_pong_ids_received?
      @client_ids == @client_pong_ids_received
    end

    def all_client_invalidated_ids_received?
      @client_ids == @client_invalidated_ids_received
    end

    def switch_master
      if new_master = detect_new_master
        msg = "Setting redis master to '#{new_master.server}' (was '#{current_master.server}')"
        logger.warn(msg)
        beetle.publish(:system_notification, {"message" => msg}.to_json)

        new_master.master!
        @current_master = new_master
      else
        msg = "Redis master could not be switched, no slave available to become new master, promoting old master"
        logger.error(msg)
        beetle.publish(:system_notification, {"message" => msg}.to_json)
      end

      publish_master(current_master)
      master_watcher.continue
    end

    def publish_master(master)
      logger.info "Publishing reconfigure message with server '#{master.server}'"
      beetle.publish(:reconfigure, payload_with_current_token({"server" => master.server}))
    end

    def configure_slaves(master)
      (redis.masters-[master]).each do |r|
        logger.info "Reconfiguring '#{r.server}' as a slave of '#{master.server}'"
        r.slave_of!(master.host, master.port)
      end
    end

    class RedisWatcher #:nodoc:
      include Logging

      def initialize(configuration_server)
        @configuration_server = configuration_server
        @retries = 0
        @paused = true
        @master_retry_interval = configuration_server.config.redis_configuration_master_retry_interval
        @master_retries = configuration_server.config.redis_configuration_master_retries
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
            logger.info "Start watching redis servers every #{@master_retry_interval} seconds"
            EventMachine::add_periodic_timer(@master_retry_interval) { check_availability }
          end
        @paused = false
      end
      alias continue watch

      def paused?
        @paused
      end

      private
      def check_availability
        @configuration_server.redis.refresh
        if @configuration_server.master_available?
          @configuration_server.master_available!
        else
          logger.warn "Redis master not available! (Retries left: #{@master_retries - (@retries + 1)})"
          if (@retries+=1) >= @master_retries
            @retries = 0
            @configuration_server.master_unavailable!
          end
        end
      end
    end
  end
end
