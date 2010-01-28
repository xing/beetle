module Bandersnatch
  class Subscriber < Base
    attr_accessor :handlers

    def initialize(client, options = {})
      super
      @handlers = {}
      @queues = {}
    end

    def listen(messages=@messages.keys)
      EM.run do
        create_exchanges(messages)
        bind_queues(messages)
        subscribe
      end
    end

    def subscribe(messages=nil)
      messages ||= @client.messages.keys
      Array(messages).each do |message|
        @servers.each do |s|
          set_current_server s
          subscribe_message(message)
        end
      end
    end

    def register_handler(messages, opts, &block)
      Array(messages).each do |message|
        (@handlers[message] ||= []) << [opts.symbolize_keys, block]
      end
    end

    private
    def bind_queues(messages)
      @servers.each do |s|
        set_current_server s
        queues_with_handlers(messages).each do |name|
          bind_queue(name)
        end
      end
    end

    def queues_with_handlers(messages)
      messages.map do |name|
        @handlers[name].map {|opts, _| opts[:queue] || name }
      end.flatten
    end

    def queues
      @queues[@server] ||= {}
    end

    QUEUE_CREATION_KEYS = [:passive, :durable, :exclusive, :auto_delete, :no_wait]
    QUEUE_BINDING_KEYS = [:key, :no_wait]

    def bind_queue(name, trace = false)
      logger.debug("Binding #{name}")
      opts = @amqp_config["queues"][name].dup
      opts.symbolize_keys!
      exchange_name = opts.delete(:exchange) || name
      queue_name = name
      if @trace
        opts.merge!(:durable => true, :auto_delete => true)
        queue_name = "trace-#{name}-#{`hostname`.chomp}"
      end
      binding_keys = opts.slice(*QUEUE_BINDING_KEYS)
      creation_keys = opts.slice(*QUEUE_CREATION_KEYS)
      queues[name] = bind_queue!(queue_name, creation_keys, exchange_name, binding_keys)
    end

    def mq
      @mqs[@server] ||= MQ.new(amqp_connection)
    end

    def subscribe_message(message)
      handlers = Array(@handlers[message])
      error("no handler for message #{message}") if handlers.empty?
      handlers.each do |opts, block|
        opts = opts.dup
        key = opts.delete(:key) || message
        queue = opts.delete(:queue) || message
        callback = create_subscription_callback(@server, queue, block)
        logger.debug "subscribing to queue #{queue} with key #{key} for message #{message}"
        begin
          queues[queue].subscribe(opts.merge(:key => "#{key}.#"), &callback)
        rescue MQ::Error
          error("Binding multiple handlers for the same queue isn't possible. You might want to use the :queue option")
        end
      end
    end

    def create_subscription_callback(server, queue, block)
      lambda do |header,data|
        begin
          message = Message.new(server, header, data)

          if message.expired?
            logger.warn "Message expired: #{message.uuid}"
          elsif message.insert_id(queue)
            begin
              block.call(message)
            rescue Exception
              logger.warn "Error during invocation of message handler for #{message}"
            end
          end

          header.ack
        rescue Exception
          logger.error "Error during message processing. Message will get redelivered. #{message}\n #{$!}"
          @timer.cancel if @timer
          @timer = EM::Timer.new(RECOVER_AFTER) do
            logger.info "Redelivering unacked messages that could not be verified because of unavailable Redis"
            @mqs[server].recover(true)
          end
        end
      end
    end

    def create_exchange!(name, opts)
      mq.__send__(opts[:type], name, opts.slice(*EXCHANGE_CREATION_KEYS))
    end

    def bind_queue!(queue_name, creation_keys, exchange_name, binding_keys)
      queue = mq.queue(queue_name, creation_keys)
      queue.bind(exchange(exchange_name), binding_keys)
      queue
    end

    def stop!
      @amqp_connections.each_value{|c| c.close}
      @amqp_connections = {}
      @mqs = {}
      EM.stop_event_loop
    end

    def new_amqp_connection
      AMQP.connect(:host => current_host, :port => current_port)
    end

    def amqp_connection
      @amqp_connections[@server] ||= new_amqp_connection
    end
  end
end