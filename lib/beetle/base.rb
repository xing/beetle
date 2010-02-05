module Beetle
  # TODO TODO TODO FIXME
  # Refactorings incomming.
  # * extract to publisher and subscriber base classes
  # * only keep the neccassary code in Base
  class Base

    QUEUE_CREATION_KEYS = [:passive, :durable, :exclusive, :auto_delete, :no_wait]
    QUEUE_BINDING_KEYS  = [:key, :no_wait]

    attr_accessor :options, :exchanges, :queues, :trace, :servers, :server, :messages, :amqp_config

    def initialize(client, options = {})
      @options = options
      @client = client
      @servers = @client.servers
      @messages = @client.messages
      @amqp_config = @client.amqp_config
      @server = @servers[rand @servers.size]
      @exchanges = {}
      @queue_names_for_exchange = {}
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

    def register_queue(name, opts)
      @amqp_config["queues"][name] = opts.symbolize_keys
    end

    def exchanges_for_current_server
      @exchanges[@server] ||= {}
    end

    def queue_names_for_exchange_name(exchange_name)
      @queue_names_for_exchange[exchange_name] ||=
        amqp_config["queues"].select{|queue, config| config["exchange"] == exchange_name || (config["exchange"].blank? && queue == exchange_name)}.map(&:first)
    end

    def queue_name_for_message_name(message_name)
      ((m = @amqp_config["messages"][message_name]) && m["queue"]) || message_name
    end

    def exchange_name_for_queue_name(queue_name)
      ((q = @amqp_config["queues"][queue_name]) && q["exchange"]) || queue_name
    end

    def exchange_name_for_message_name(message_name)
      exchange_name_for_queue_name(queue_name_for_message_name(message_name))
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
        messages.each do |message|
          create_exchange(exchange_name_for_message_name(message))
        end
      end
    end

    def create_exchange(name)
      opts = @amqp_config["exchanges"][name].symbolize_keys
      opts[:type] = opts[:type].to_sym
      exchanges_for_current_server[name] = create_exchange!(name, opts)
    end

    def queues
      @queues[@server] ||= {}
    end

    def queue_bound?(queue_name)
      !!queues[queue_name]
    end

    def bind_queue(name, trace = false)
      queues[name] ||=
        begin
          logger.debug("Binding #{name}")
          queue_opts = @amqp_config["queues"][name]
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
