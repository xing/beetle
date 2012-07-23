module Beetle
  # A RedisConfigurationClient is the subordinate part of beetle's
  # redis failover solution
  #
  # An instance of RedisConfigurationClient lives on every server that
  # hosts message consumers (worker server).
  #
  # It is responsible for determining an initial redis master and reacting to redis master
  # switches initiated by the RedisConfigurationServer.
  #
  # It will write the current redis master host:port string to a file specified via a
  # Configuration, which is then read by DeduplicationStore on redis access.
  #
  # Usually started via <tt>beetle configuration_client</tt> command.
  class RedisConfigurationClient
    include Logging
    include RedisMasterFile

    # Set a custom unique id for this instance. Must match an entry in
    # Configuration#redis_configuration_client_ids.
    attr_writer :id

    # The current redis master
    attr_reader :current_master

    # Unique id for this instance (defaults to the fully qualified hostname)
    def id
      @id ||= Beetle.hostname
    end

    def initialize #:nodoc:
      @current_token = nil
      MessageDispatcher.configuration_client = self
    end

    # determinines the initial redis master (if possible), then enters a messaging event
    # loop, reacting to failover related messages sent by RedisConfigurationServer.
    def start
      verify_redis_master_file_string
      client_started!
      logger.info "RedisConfigurationClient starting (client id: #{id})"
      determine_initial_master
      clear_redis_master_file unless current_master.try(:master?)
      logger.info "Listening"
      beetle.listen
    end

    # called by the message dispatcher when a "pong" message from RedisConfigurationServer is received
    def ping(payload)
      token = payload["token"]
      logger.info "Received ping message with token '#{token}'"
      pong! if redeem_token(token)
    end

    # called by the message dispatcher when a "invalidate" message from RedisConfigurationServer is received
    def invalidate(payload)
      token = payload["token"]
      logger.info "Received invalidate message with token '#{token}'"
      invalidate! if redeem_token(token) && !current_master.try(:master?)
    end

    # called by the message dispatcher when a "reconfigure"" message from RedisConfigurationServer is received
    def reconfigure(payload)
      server = payload["server"]
      token = payload["token"]
      logger.info "Received reconfigure message with server '#{server}' and token '#{token}'"
      return unless redeem_token(token)
      unless server == read_redis_master_file
        new_master!(server)
        write_redis_master_file(server)
      end
    end

    # Beetle::Client instance for communication with the RedisConfigurationServer
    def beetle
      @beetle ||= build_beetle
    end

    def config #:nodoc:
      beetle.config
    end

    private

    def determine_initial_master
      if master_file_exists? && server = read_redis_master_file
        new_master!(server)
      end
    end

    def new_master!(server)
      @current_master = Redis.from_server_string(server, :timeout => 3)
    end

    def build_beetle
      system = Beetle.config.system_name
      Beetle::Client.new.configure :exchange => system, :auto_delete => true do |config|
        config.message :ping
        config.queue   :ping, :amqp_name => "#{system}_ping_#{id}"
        config.message :pong
        config.message :invalidate
        config.queue   :invalidate, :amqp_name => "#{system}_invalidate_#{id}"
        config.message :client_invalidated
        config.message :reconfigure
        config.queue   :reconfigure, :amqp_name => "#{system}_reconfigure_#{id}"
        config.message :client_started

        config.handler [:ping, :invalidate, :reconfigure], MessageDispatcher
      end
    end

    def redeem_token(token)
      @current_token = token if @current_token.nil? || token > @current_token
      token_valid = token >= @current_token
      logger.info "Ignored message (token was '#{token}', but expected to be >= '#{@current_token}')" unless token_valid
      token_valid
    end

    def pong!
      logger.info "Sending pong message with id '#{id}' and token '#{@current_token}'"
      beetle.publish(:pong, {"id" => id, "token" => @current_token}.to_json)
    end

    def client_started!
      logger.info "Sending client_started message with id '#{id}'"
      beetle.publish(:client_started, {"id" => id}.to_json)
    end

    def invalidate!
      @current_master = nil
      clear_redis_master_file
      logger.info "Sending client_invalidated message with id '#{id}' and token '#{@current_token}'"
      beetle.publish(:client_invalidated, {"id" => id, "token" => @current_token}.to_json)
    end


    # Dispatches messages from the queue to methods in RedisConfigurationClient
    class MessageDispatcher < Beetle::Handler #:nodoc:
      cattr_accessor :configuration_client
      def process
        @@configuration_client.__send__(message.header.routing_key, ActiveSupport::JSON.decode(message.data))
      end
    end
  end
end
