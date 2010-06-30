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

    # The current redis master
    attr_reader :redis_master

    # The current token used to detect correct message order
    attr_reader :current_token

    # redis_server_strings is an array of host:port strings,
    # e.g. ["192.168.1.2:6379", "192.168.1.3:6379"]
    #
    # Exactly one of them must be a redis master.
    def initialize(redis_server_strings = [])
      @redis_server_strings = redis_server_strings
      @client_ids = Set.new(Beetle.config.redis_configuration_client_ids.split(","))
      @current_token = (Time.now.to_f * 1000).to_i
      @client_pong_ids_received = Set.new
      @client_invalidated_ids_received = Set.new
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
      logger.info "AMQP servers  : #{Beetle.config.servers}"
      logger.info "Client ids    : #{Beetle.config.redis_configuration_client_ids}"
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
    def redis_unavailable
      msg = "Redis master '#{redis_master.server}' not available"
      redis_master_watcher.pause
      logger.warn(msg)
      beetle_client.publish(:system_notification, {"message" => msg}.to_json)

      if @client_ids.empty?
        switch_master
      else
        start_invalidation
      end
    end

    private

    def beetle_client
      @beetle_client ||= build_beetle_client
    end

    def build_beetle_client
      beetle_client = Beetle::Client.new
      beetle_client.configure :exchange => :system, :auto_delete => true do |config|
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
      beetle_client
    end

    def redis_master_watcher
      @redis_master_watcher ||= RedisWatcher.new(redis_master, self)
    end

    def redis_master
      @redis_master ||= initial_redis_master
    end

    def initial_redis_master
      # TODO
      # * what if no initial master available?
      # * what if more than one master? (reuse auto-detection of client?)
      all_available_redis.find{|redis| redis.master? }
    end

    def all_available_redis
      all_redis.select{|redis| redis.available? }
    end

    def all_redis
      @all_redis ||= @redis_server_strings.map{|r| Redis.from_server_string(r) }
    end

    def new_redis_master
      @new_redis_master ||= redis_slaves.first
    end

    def redis_slaves
      all_available_redis.select{|redis| redis.slave_of?(redis_master.host, redis_master.port) }
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
      @available_timer = EM::Timer.new(Beetle.config.redis_configuration_client_timeout) { cancel_invalidation }
    end

    def invalidate_current_master
      generate_new_token
      beetle_client.publish(:invalidate, {"token" => @current_token}.to_json)
      @invalidate_timer = EM::Timer.new(Beetle.config.redis_configuration_client_timeout) { cancel_invalidation }
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
      if new_redis_master
        msg = "Redis master switched from '#{@redis_master.server}' to '#{new_redis_master.server}'"
        logger.warn(msg)
        beetle_client.publish(:system_notification, {"message" => msg}.to_json)

        new_redis_master.master!
        publish_master(new_redis_master)
        @redis_master = Redis.new(:host => new_redis_master.host, :port => new_redis_master.port)
        @new_redis_master = nil

        redis_master_watcher.redis = redis_master
      else
        msg = "Redis master could not be switched, no slave available to become new master, promoting old master"
        logger.error(msg)
        beetle_client.publish(:system_notification, {"message" => msg}.to_json)
        publish_master(redis_master)
      end
      redis_master_watcher.continue
    end

    def publish_master(promoted_server)
      logger.info "Publishing reconfigure message with host '#{promoted_server.host}' port '#{promoted_server.port}'"
      beetle_client.publish(:reconfigure, {:host => promoted_server.host, :port => promoted_server.port}.to_json)
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

      attr_accessor :redis

      def initialize(redis, configuration_server)
        @redis = redis
        @configuration_server = configuration_server
        @retries = 0
        @paused = true
      end

      def pause
        logger.info "Pause checking availability of redis '#{@redis.server}'"
        @watch_timer.cancel if @watch_timer
        @watch_timer = nil
        @paused = true
      end

      def watch
        @watch_timer ||= begin
          logger.info "Start watching #{@redis.server} every #{Beetle.config.redis_configuration_master_retry_timeout} seconds" if @redis
          EventMachine::add_periodic_timer(Beetle.config.redis_configuration_master_retry_timeout) {
            if @redis
              logger.debug "Checking availability of redis '#{@redis.server}'"
              unless @redis.available?
                logger.warn "Redis server #{@redis.server} not available! (Retries left: #{Beetle.config.redis_configuration_master_retries - (@retries + 1)})"
                if (@retries+=1) >= Beetle.config.redis_configuration_master_retries
                  @retries = 0
                  @configuration_server.redis_unavailable
                end
              end
            end
          }
        end
        @paused = false
      end
      alias continue watch

      def paused?
        @paused
      end
    end
  end
end
