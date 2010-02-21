module Beetle
  class Subscriber < Base

    RECOVER_AFTER = 1.seconds

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
        callback = create_subscription_callback(message, queue_name_for_trace(queue), handler, opts)
        logger.debug "Beetle: subscribing to queue #{queue_name_for_trace(queue)} with key #{key} for message #{message}"
        begin
          queues[queue].subscribe(opts.merge(:key => "#{key}.#", :ack => true), &callback)
        rescue MQ::Error
          error("Beetle: binding multiple handlers for the same queue isn't possible. You might want to use the :queue option")
        end
      end
    end

    def create_subscription_callback(message, queue, handler, opts)
      server = @server
      lambda do |header, data|
        begin
          processor = Handler.create(handler, opts)
          m = Message.new(queue, header, data, opts.merge(:server => server))
          result = m.process(processor)
          if result.recover?
            sleep 0.1
            @client.send(:publisher).re_publish(server, message, data, :key => "delayed.#{queue}.#{opts[:key]}")
            header.ack
          end
        rescue Exception
          Beetle::reraise_expectation_errors!
          # swallow all exceptions
          logger.error "Beetle: internal error during message processing: #{$!}"
        end
      end
    end

    def create_exchange!(name, opts)
      mq.__send__(opts[:type], name, opts.slice(*EXCHANGE_CREATION_KEYS))
    end

    def bind_queue!(queue_name, creation_keys, exchange_name, binding_keys)
      queue = mq.queue(queue_name, creation_keys)
      exchange = exchange(exchange_name)
      queue.bind(exchange, binding_keys)
      queue.bind(exchange, binding_keys.merge(:key => "delayed.#{queue_name}.#")) if binding_keys[:key] != "#"
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
