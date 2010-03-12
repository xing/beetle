module Beetle
  # Manages subscriptions and message processing on the receiver side of things.
  class Subscriber < Base

    # create a new subscriber instance
    def initialize(client, options = {}) #:nodoc:
      super
      @handlers = {}
      @amqp_connections = {}
      @mqs = {}
    end

    # the client calls this to subcsribe to all queues on all servers which have handlers
    # registered fo the given list of messages (defaults to all messages defined on the
    # client). this method does the follwing things:
    #
    # * creates all exchanges which have been registerd for the messages
    # * creates and binds queues which have been registered for the exchanges
    # * subscribes the handlers for all these queues
    #
    # yields before entering the eventmachine loop (if a block was given)
    def listen(messages=@client.messages.keys) #:nodoc:
      EM.run do
        create_exchanges(messages)
        bind_queues(messages)
        subscribe(messages)
        yield if block_given?
      end
    end

    # stops the eventmachine loop
    def stop! #:nodoc:
      EM.stop_event_loop
    end

    # register handler for the given messages (see Client#register_handler)
    def register_handler(messages, opts={}, handler=nil, &block) #:nodoc:
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

    # returns the mq object for the given server or returns a new one created with the
    # prefetch(1) option. this tells it to just send one message to the receiving buffer
    # (instead of filling it). this is necesssary to ensure that one subscriber always just
    # handles one single message. we cannot ensure reliability if the buffer is filled with
    # messages and crashes.
    def mq(server=@server)
      @mqs[server] ||= MQ.new(amqp_connection).prefetch(1)
    end

    def subscribe_message(message)
      handlers = Array(@handlers[message])
      error("no handler for message #{message}") if handlers.empty?
      handlers.each do |opts, handler|
        queue_name = opts[:queue] || message
        queue_opts = @client.queues[queue_name]
        amqp_queue_name = queue_opts[:amqp_name]
        callback = create_subscription_callback(message, amqp_queue_name, handler, opts)
        logger.debug "Beetle: subscribing to queue #{amqp_queue_name} with key # for message #{message}"
        begin
          queues[queue_name].subscribe(opts.slice(*SUBSCRIPTION_KEYS).merge(:key => "#", :ack => true), &callback)
        rescue MQ::Error
          error("Beetle: binding multiple handlers for the same queue isn't possible. You might want to use the :queue option")
        end
      end
    end

    def create_subscription_callback(message, amqp_queue_name, handler, opts)
      server = @server
      lambda do |header, data|
        begin
          processor = Handler.create(handler, opts)
          m = Message.new(amqp_queue_name, header, data, opts.merge(:server => server))
          result = m.process(processor)
          if result.recover?
            sleep 1
            mq(server).recover
          elsif reply_to = header.properties[:reply_to]
            status = result == Beetle::RC::OK ? "OK" : "FAILED"
            exchange = MQ::Exchange.new(mq(server), :direct, "", :key => reply_to)
            exchange.publish(m.handler_result.to_s, :headers => {:status => status})
          end
        rescue Exception
          Beetle::reraise_expectation_errors!
          # swallow all exceptions
          logger.error "Beetle: internal error during message processing: #{$!}: #{$!.backtrace.join("\n")}"
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
      queue
    end

    def amqp_connection(server=@server)
      @amqp_connections[server] ||= new_amqp_connection
    end

    def new_amqp_connection
      # FIXME: wtf, how to test that reconnection feature....
      con = AMQP.connect(:host => current_host, :port => current_port)
      con.instance_variable_set("@on_disconnect", proc{ con.__send__(:reconnect) })
      con
    end

  end
end
