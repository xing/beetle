module Beetle
  class Subscriber < Base

    RECOVER_AFTER = 10.seconds

    def initialize(client, options = {})
      super
      @handlers = {}
      @amqp_connections = {}
      @mqs = {}
      @timer_rewinds = Hash.new(0)
      @timers = {}
    end

    def listen(messages=@client.messages.keys)
      EM.run do
        create_exchanges(messages)
        bind_queues(messages)
        subscribe(messages)
        yield if block_given?
      end
    end

    def register_handler(messages, opts, handler=nil, &block)
      Array(messages).each do |message|
        (@handlers[message] ||= []) << [opts.symbolize_keys, handler || block]
      end
    end

    private

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
        callback = create_subscription_callback(@server, queue_name_for_trace(queue), handler, opts)
        logger.debug "Beetle: subscribing to queue #{queue_name_for_trace(queue)} with key #{key} for message #{message}"
        begin
          queues[queue].subscribe(opts.merge(:key => "#{key}.#", :ack => true), &callback)
        rescue MQ::Error
          error("Beetle: binding multiple handlers for the same queue isn't possible. You might want to use the :queue option")
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
          Beetle::reraise_expectation_errors!
          # swallow all exceptions
          logger.error "Beetle: internal error during message processing: #{$!}"
        end
      end
    end

    # rewind the message recovery timer for a given server with increasing time intervals, but at most 3 times
    def install_recovery_timer(server)
      return if (@timer_rewinds[server] += 1) > 3
      @timers[server].cancel if @timers[server]
      @timers[server] = new_recovery_timer(server, @timer_rewinds[server] * RECOVER_AFTER)
    end

    def new_recovery_timer(server, seconds)
      EM::Timer.new(seconds) do
        @timers[server] = nil
        @timer_rewinds[server] = 0
        logger.info "Beetle: recovering unacked messages"
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
