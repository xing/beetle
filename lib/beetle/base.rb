module Beetle
  # Abstract base class shared by Publisher and Subscriber
  class Base
    include Logging

    attr_accessor :options, :servers, :server  #:nodoc:

    def initialize(client, options = {}) #:nodoc:
      @options = options
      @client = client
      @servers = @client.servers.clone
      @server = @servers[rand @servers.size]
      @exchanges = {}
      @queues = {}
      @dead_lettering = DeadLettering.new(@client)
    end

    private

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

    def server_from_settings(settings)
      settings.values_at(:host,:port).join(':')
    end

    def each_server
      @servers.each { |s| set_current_server(s); yield }
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

    QueueInfo = Struct.new(:queue, :create_policies)

    def queue(name, create_policies: false)
      info = queues[name]
      if info && create_policies && !info.create_policies
        queues.delete(name)
      end
      queues[name] ||=
        begin
          opts = @client.queues[name]
          raise UnknownQueue.new("You are trying to bind a queue #{name} which is not configured!") unless opts
          logger.debug("Beetle: binding queue #{name} with internal name #{opts[:amqp_name]} on server #{@server}")
          queue_name = opts[:amqp_name]
          creation_options = opts.slice(*QUEUE_CREATION_KEYS)
          the_queue = nil
          @client.bindings[name].each do |binding_options|
            exchange_name = binding_options[:exchange]
            binding_options = binding_options.slice(*QUEUE_BINDING_KEYS)
            the_queue = bind_queue!(queue_name, creation_options, exchange_name, binding_options, create_policies: create_policies)
          end
          info = QueueInfo.new(the_queue, create_policies)
        end
      info.queue
    end

  end
end
