module Beetle
  # TODO TODO TODO FIXME
  # Refactorings incomming.
  # * extract to publisher and subscriber base classes
  # * only keep the neccassary code in Base
  class Base

    QUEUE_CREATION_KEYS = [:passive, :durable, :exclusive, :auto_delete, :no_wait]
    QUEUE_BINDING_KEYS  = [:key, :no_wait]

    attr_accessor :options, :trace, :servers, :server

    def initialize(client, options = {})
      @options = options
      @client = client
      @servers = @client.servers
      @server = @servers[rand @servers.size]
      @exchanges = {}
      @queues = {}
      @trace = false
    end

    def stop
      stop!
    end

    private

    def error(text)
      logger.error text
      raise Error.new(text)
    end

    def bind_queues(messages)
      @servers.each do |s|
        set_current_server s
        queues_with_handlers(messages).each do |name|
          bind_queue(name)
        end
      end
    end

    def exchanges
      @exchanges[@server] ||= {}
    end

    def exchange(name)
      create_exchange(name) unless exchange_exists?(name)
      exchanges[name]
    end

    def exchange_exists?(name)
      exchanges.include?(name)
    end

    def create_exchange(name)
      exchanges[name] = create_exchange!(name, @client.exchanges[name])
    end

    def queues
      @queues[@server] ||= {}
    end

    def bind_queue(name)
      queues[name] ||=
        begin
          logger.debug("Binding #{name}")
          queue_opts = @client.queues[name]
          error("You are trying to bind a queue '#{name}' which is not configured!") unless queue_opts
          opts = queue_opts.dup
          opts.symbolize_keys!
          exchange_name = opts.delete(:exchange) || name
          queue_name = name
          if @trace
            opts.merge!(:durable => true, :auto_delete => true)
            queue_name = "trace-#{name}-#{`hostname`.chomp}"
          end
          binding_keys = opts.slice(*QUEUE_BINDING_KEYS)
          creation_keys = opts.slice(*QUEUE_CREATION_KEYS)
          bind_queue!(queue_name, creation_keys, exchange_name, binding_keys)
        end
    end

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
      Beetle.config.logger
    end
  end
end
