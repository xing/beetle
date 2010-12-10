module Beetle
  # Manages subscriptions and message processing on the receiver side of things.
  class Subscriber < Base

    # create a new subscriber instance
    def initialize(client, options = {}) #:nodoc:
      super
      @servers.concat @client.additional_subscription_servers
      @handlers = {}
      @amqp_connections = {}
      @mqs = {}
    end

    # the client calls this method to subscribe to all queues on all servers which have
    # handlers registered for the given list of messages. this method does the following
    # things:
    #
    # * creates all exchanges which have been registered for the given messages
    # * creates and binds queues which have been registered for the exchanges
    # * subscribes the handlers for all these queues
    #
    # yields before entering the eventmachine loop (if a block was given)
    def listen(messages) #:nodoc:
      EM.run do
        exchanges = exchanges_for_messages(messages)
        create_exchanges(exchanges)
        queues = queues_for_exchanges(exchanges)
        bind_queues(queues)
        subscribe_queues(queues)
        yield if block_given?
      end
    end

    # closes all AMQP connections and stops the eventmachine loop
    def stop! #:nodoc:
      if @amqp_connections.empty?
        EM.stop_event_loop
      else
        server, connection = @amqp_connections.shift
        connection.close { stop! }
      end
    end

    # register handler for the given queues (see Client#register_handler)
    def register_handler(queues, opts={}, handler=nil, &block) #:nodoc:
      Array(queues).each do |queue|
        @handlers[queue] = [opts.symbolize_keys, handler || block]
      end
    end

    private

    def exchanges_for_messages(messages)
      @client.messages.slice(*messages).map{|_, opts| opts[:exchange]}.uniq
    end

    def queues_for_exchanges(exchanges)
      @client.exchanges.slice(*exchanges).map{|_, opts| opts[:queues]}.flatten.compact.uniq
    end

    def create_exchanges(exchanges)
      each_server do
        exchanges.each { |name| exchange(name) }
      end
    end

    def bind_queues(queues)
      each_server do
        queues.each { |name| queue(name) }
      end
    end

    def subscribe_queues(queues)
      each_server do
        queues.each { |name| subscribe(name) if @handlers.include?(name) }
      end
    end

    # returns the mq object for the given server or returns a new one created with the
    # prefetch(1) option. this tells it to just send one message to the receiving buffer
    # (instead of filling it). this is necesssary to ensure that one subscriber always just
    # handles one single message. we cannot ensure reliability if the buffer is filled with
    # messages and crashes.
    def mq(server=@server)
      @mqs[server] ||= MQ.new(amqp_connection).prefetch(1)
    end

    def subscribe(queue_name)
      error("no handler for queue #{queue_name}") unless @handlers.include?(queue_name)
      opts, handler = @handlers[queue_name]
      queue_opts = @client.queues[queue_name][:amqp_name]
      amqp_queue_name = queue_opts
      callback = create_subscription_callback(queue_name, amqp_queue_name, handler, opts)
      logger.debug "Beetle: subscribing to queue #{amqp_queue_name} with key # on server #{@server}"
      begin
        queues[queue_name].subscribe(opts.slice(*SUBSCRIPTION_KEYS).merge(:key => "#", :ack => true), &callback)
      rescue MQ::Error
        error("Beetle: binding multiple handlers for the same queue isn't possible.")
      end
    end

    def create_subscription_callback(queue_name, amqp_queue_name, handler, opts)
      server = @server
      lambda do |header, data|
        begin
          processor = Handler.create(handler, opts)
          message_options = opts.merge(:server => server, :store => @client.deduplication_store)
          m = Message.new(amqp_queue_name, header, data, message_options)
          result = m.process(processor)
          if result.reject?
            sleep 1
            header.reject(:requeue => true)
          elsif reply_to = header.properties[:reply_to]
            # require 'ruby-debug'
            # Debugger.start
            # debugger
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
      con = AMQP.connect(:host => current_host, :port => current_port,
                         :user => Beetle.config.user, :pass => Beetle.config.password, :vhost => Beetle.config.vhost)
      con.instance_variable_set("@on_disconnect", proc{ con.__send__(:reconnect) })
      con
    end

  end
end
