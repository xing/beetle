module Beetle
  # A RedisConfigurationClient is the subordinate part of beetle's
  # redis failover solution
  #
  # An instances of RedisConfigurationClient lives on every server that
  # hosts beetle consumers (worker server).
  # A RedisConfigurationClient is responsible for determining an initial
  # redis master and reacting to redis master switches initiated by the
  # RedisConfigurationServer.
  #
  # It will write the current redis master host:port string to a file
  # specified via Configuration#redis_server, which is then read by
  # DeduplicationStore on redis access.
  #
  # Usually started via <tt>beetle configuration_client</tt> command.
  class RedisConfigurationClient < Beetle::Handler
    include Logging
    include RedisMasterFile
    include RedisConfigurationAutoDetection

    # Set a custom unique id for this instance
    #
    # Must match an entry in Configuration#redis_configuration_client_ids
    # for a redis failover to work.
    attr_writer :id

    # Unique id for this instance (defaults to the hostname)
    def id
      @id ||= `hostname`.chomp
    end

    def initialize
      @current_token = nil
      RedisConfigurationServerMessageHandler.configuration_client = self
    end

    # Start determining initial redis master and reacting
    # to failover related messages sent by RedisConfigurationServer
    def start
      logger.info "RedisConfigurationClient Starting (#{id})"
      clear_redis_master_file
      @redis_master = auto_detect_master
      write_redis_master_file(@redis_master.server) if @redis_master
      logger.info "Listening"
      beetle_client.listen
    end

    # Method called from RedisConfigurationServerMessageHandler
    # when "pong" message from RedisConfigurationServer is received
    def ping(payload)
      token = payload["token"]
      logger.info "Received ping message with token '#{token}'"
      pong! if redeem_token(token)
    end

    # Method called from RedisConfigurationServerMessageHandler
    # when "invalidate" message from RedisConfigurationServer is received
    def invalidate(payload)
      token = payload["token"]
      logger.info "Received invalidate message with token '#{token}'"
      invalidate! if redeem_token(token)
    end

    # Method called from RedisConfigurationServerMessageHandler
    # when "reconfigure"" message from RedisConfigurationServer is received
    def reconfigure(payload)
      server = payload["server"]
      token = payload["token"]
      logger.info "Received reconfigure message with server '#{server}' and token '#{token}'"
      return unless redeem_token(token)
      unless server == read_redis_master_file
        write_redis_master_file(server)
        @redis_master = Redis.from_server_string(server)
      end
    end

    private

    def beetle_client
      @beetle_client ||= build_beetle_client
    end

    def build_beetle_client
      Beetle::Client.new.configure :exchange => :system, :auto_delete => true do |config|
        config.message :ping
        config.queue   internal_queue_name(:ping), :key => "ping"
        config.message :pong
        config.message :invalidate
        config.queue   internal_queue_name(:invalidate), :key => "invalidate"
        config.message :client_invalidated
        config.message :reconfigure
        config.queue   internal_queue_name(:reconfigure), :key => "reconfigure"

        config.handler(internal_queue_name(:ping),        RedisConfigurationServerMessageHandler)
        config.handler(internal_queue_name(:invalidate),  RedisConfigurationServerMessageHandler)
        config.handler(internal_queue_name(:reconfigure), RedisConfigurationServerMessageHandler)
      end
    end

    def internal_queue_name(prefix)
      "#{prefix}-#{id}"
    end

    def redeem_token(token)
      @current_token = token if @current_token.nil? || token > @current_token
      token_valid = token >= @current_token
      logger.info "Ignored message (token was '#{token}', but expected to be >= '#{@current_token}')" unless token_valid
      token_valid
    end

    def pong!
      beetle_client.publish(:pong, {"id" => id, "token" => @current_token}.to_json)
    end

    def invalidate!
      clear_redis_master_file
      @redis_master = nil
      beetle_client.publish(:client_invalidated, {"id" => id, "token" => @current_token}.to_json)
    end

    def redis_instances
      @redis_instances ||= beetle_client.config.redis_server_list.map{|s| Redis.from_server_string(s, :timeout => 3) }
    end
  end

  class RedisConfigurationServerMessageHandler < Beetle::Handler #:nodoc:
    cattr_accessor :configuration_client

    def process
      self.class.configuration_client.__send__(message.header.routing_key, ActiveSupport::JSON.decode(message.data))
    end
  end
end
