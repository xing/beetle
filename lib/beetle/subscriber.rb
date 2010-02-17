module Beetle
  class Subscriber < Base

    RECOVER_AFTER = 10.seconds

    def initialize(client, options = {})
      super
      @handlers = {}
      @amqp_connections = {}
      @mqs = {}
    end

    def listen(messages=@client.messages.keys)
      EM.run do
        create_exchanges(messages)
        bind_queues(messages)
        subscribe(messages)
      end
    end

    def register_handler(messages, opts, handler=nil, &block)
      Array(messages).each do |message|
        (@handlers[message] ||= []) << [opts.symbolize_keys, handler || block]
      end
    end

    private

    def each_server
      @servers.each { |s| set_current_server(s); yield }
    end

    def create_exchanges(messages)
      each_server do
        messages.each { |message| exchange(@client.messages[message][:exchange]) }
      end
    end

    def bind_queues(messages)
      each_server do
        queues_with_handlers(messages).each { |name| queue(name) }
      end
    end

    def subscribe(messages)
      each_server do
        Array(messages).each { |message| subscribe_message(message) }
      end
    end

    def queues_with_handlers(messages)
      messages.map { |name| @handlers[name].map {|opts, _| opts[:queue] || name } }.flatten
    end

    def mq(server=@server)
      @mqs[server] ||= MQ.new(amqp_connection).prefetch(1)
    end

    def subscribe_message(message)
      handlers = Array(@handlers[message])
      error("no handler for message #{message}") if handlers.empty?
      handlers.each do |opts, handler|
        opts = opts.dup
        key = opts.delete(:key) || message
        queue = opts.delete(:queue) || message
        callback = create_subscription_callback(@server, queue, handler, opts)
        logger.debug "subscribing to queue #{queue} with key #{key} for message #{message}"
        begin
          queues[queue].subscribe(opts.merge(:key => "#{key}.#", :ack => true), &callback)
        rescue MQ::Error
          error("Binding multiple handlers for the same queue isn't possible. You might want to use the :queue option")
        end
      end
    end

    def create_subscription_callback(server, queue, handler, opts)
      lambda do |header, data|
        begin
          processor = Handler.create(handler, opts)
          m = Message.new(queue, header, data, opts.merge(:server => server))
          result = m.process(processor)
          install_recovery_timer(server) if result.recover?
        rescue Exception
          # swallow all exceptions
          logger.error "Internal error during message processing"
        end
      end
    end

    def install_recovery_timer(server)
      @timer.cancel if @timer
      @timer = EM::Timer.new(RECOVER_AFTER) do
        logger.info "Redelivering unacked messages"
        mq(server).recover(true)
        # this resets the exchanges and queues for this server
        # it ensures that the subscriber rehandles the message even when prefetch(1) is set
        mq(server).reset
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
      EM.stop_event_loop
    end

    def amqp_connection
      @amqp_connections[@server] ||= new_amqp_connection
    end

    def new_amqp_connection
      # FIXME: wtf, how to test that reconnection feature....
      con = AMQP.connect(:host => current_host, :port => current_port)
      con.instance_variable_set("@on_disconnect", proc{ con.__send__(:reconnect) })
      con
    end

  end
end
