module Bandersnatch
  class Error < StandardError; end
  #
  # TODO TODO TODO FIXME
  # Refactorings incomming.
  # * extract to publisher and subscriber base classes
  # * only keep the neccassary code in Base
  class Base

    RECOVER_AFTER = 10.seconds

    attr_accessor :options, :exchanges, :queues, :trace

    def initialize(client, options = {})
      @options = options
      @client = client
      @servers = @client.servers
      @messages = @client.messages
      @amqp_config = @client.amqp_config
      @server = @servers[rand @servers.size]
      @exchanges = {}

      @amqp_connections = {} # move to subscriber
      @mqs = {} # move to subscriber
      @trace = false
    end

    def stop
      stop!
    end

    def error(text)
      logger.error text
      raise Error.new(text)
    end

    def register_exchange(name, opts)
      @amqp_config["exchanges"][name] = opts.symbolize_keys
    end

    def register_queue(name, opts)
      @amqp_config["queues"][name] = opts.symbolize_keys
    end

    def exchanges_for_current_server
      @exchanges[@server] ||= {}
    end

    def exchange(name)
      create_exchange(name) unless exchange_exists?(name)
      exchanges_for_current_server[name]
    end

    def exchange_exists?(name)
      exchanges_for_current_server.include?(name)
    end

    def create_exchanges(messages)
      @servers.each do |s|
        set_current_server s
        messages.each do |name|
          create_exchange(name)
        end
      end
    end

    EXCHANGE_CREATION_KEYS = [:auto_delete, :durable, :internal, :nowait, :passive]

    def create_exchange(name)
      opts = @amqp_config["exchanges"][name].symbolize_keys
      opts[:type] = opts[:type].to_sym
      exchanges_for_current_server[name] = create_exchange!(name, opts)
    end

    def autoload(glob)
      Dir[glob + '/**/config/amqp_messaging.rb'].each do |f|
        eval(File.read f)
      end
    end

    private
    def current_host
      @server.split(':').first
    end

    def current_port
      @server =~ /:(\d+)$/ ? $1.to_i : 5672
    end

    def set_current_server(s)
      @server = s
    end

    def logger
      self.class.logger
    end

    def self.logger
      Bandersnatch.config.logger
    end
  end
end
