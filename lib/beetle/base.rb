module Beetle
  class Base

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

    def logger
      self.class.logger
    end

    def self.logger
      Beetle.config.logger
    end

    def error(text)
      logger.error text
      raise Error.new(text)
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

    def exchanges
      @exchanges[@server] ||= {}
    end

    def exchange(name)
      exchanges[name] ||= create_exchange!(name, @client.exchanges[name])
    end

    def queues
      @queues[@server] ||= {}
    end

    def queue(name)
      queues[name] ||=
        begin
          logger.debug("Binding #{name}")
          queue_opts = @client.queues[name]
          error("You are trying to bind a queue '#{name}' which is not configured!") unless queue_opts
          opts = queue_opts.dup
          opts.symbolize_keys!
          exchange_name = opts.delete(:exchange) || name
          opts[:auto_delete] = true if @trace
          queue_name = queue_name_for_trace(name)
          binding_keys = opts.slice(*QUEUE_BINDING_KEYS)
          creation_keys = opts.slice(*QUEUE_CREATION_KEYS)
          bind_queue!(queue_name, creation_keys, exchange_name, binding_keys)
        end
    end
    
    def queue_name_for_trace(queue)
      @trace ? "trace-#{queue}-#{`hostname`.chomp}" : queue
    end

  end
end
