require 'amqp'

module Beetle
  # Manages subscriptions and message processing on the receiver side of things.
  class Subscriber < Base

    # create a new subscriber instance
    def initialize(client, options = {}) #:nodoc:
      super
      @servers.concat @client.additional_subscription_servers
      @handlers = {}
      @connections = {}
      @channels = {}
      @subscriptions = {}
      @listened_queues = []
      @channels_closed = false
    end

    # the client calls this method to subscribe to a list of queues.
    # this method does the following things:
    #
    # * creates all exchanges which have been registered for the given queues
    # * creates and binds each listed queue queues
    # * subscribes the handlers for all these queues
    #
    # yields before entering the eventmachine loop (if a block was given)
    def listen_queues(queues) #:nodoc:
      @listened_queues = queues
      @exchanges_for_queues = exchanges_for_queues(queues)
      EM.run do
        each_server do
          connect_server connection_settings
        end
        yield if block_given?
      end
    end

    def pause_listening(queues)
      each_server do
        queues.each { |name| pause(name) if has_subscription?(name) }
      end
    end

    def resume_listening(queues)
      each_server do
        queues.each { |name| resume(name) if has_subscription?(name) }
      end
    end

    # closes all AMQP connections and stop the eventmachine loop.  note that the shutdown
    # process is asynchronous. must not be called while a message handler is
    # running. typically one would use <tt>EM.add_timer(0) { stop! }</tt> to ensure this.
    def stop! #:nodoc:
      if EM.reactor_running?
        EM.add_timer(0) do
          close_all_channels
          close_all_connections
        end
      else
        # try to clean up as much a possible under the circumstances, by closing all connections
        # this should a least close the sockets
        close_connections_with_reactor_not_running
      end
    end

    # register handler for the given queues (see Client#register_handler)
    def register_handler(queues, opts={}, handler=nil, &block) #:nodoc:
      Array(queues).each do |queue|
        @handlers[queue] = [opts.symbolize_keys, handler || block]
      end
    end

    private

    # close all sockets.
    def close_connections_with_reactor_not_running
      @connections.each { |_, connection| connection.close }
    ensure
      @connections = {}
      @channels = {}
    end

    # close all connections. this assumes the reactor is running
    def close_all_connections
      if @connections.empty?
        EM.stop_event_loop
      else
        server, connection = @connections.shift
        logger.debug "Beetle: closing connection to #{server}"
        connection.close { close_all_connections }
      end
    end

    # closes all channels. this needs to be the first action during a
    # subscriber shutdown, so that susbscription callbacks can detect
    # they should stop processing messages received from the prefetch
    # queue.
    def close_all_channels
      return if @channels_closed
      @channels.each do |server, channel|
        logger.debug "Beetle: closing channel to server #{server}"
        channel.close
      end
      @channels_closed = true
    end

    def exchanges_for_queues(queues)
      @client.bindings.slice(*queues).map{|_, opts| opts.map{|opt| opt[:exchange]}}.flatten.uniq
    end

    def queues_for_exchanges(exchanges)
      @client.exchanges.slice(*exchanges).map{|_, opts| opts[:queues]}.flatten.compact.uniq
    end

    def create_exchanges(exchanges)
      exchanges.each { |name| exchange(name) }
    end

    def bind_queues(queues)
      queues.each { |name| queue(name) }
    end

    def subscribe_queues(queues)
      queues.each { |name| subscribe(name) if @handlers.include?(name) }
    end

    def channel(server=@server)
      @channels[server]
    end

    def subscriptions(server=@server)
      @subscriptions[server] ||= {}
    end

    def has_subscription?(name)
      subscriptions.include?(name)
    end

    def subscribe(queue_name)
      error("no handler for queue #{queue_name}") unless @handlers.include?(queue_name)
      opts, handler = @handlers[queue_name]
      queue_opts = @client.queues[queue_name][:amqp_name]
      amqp_queue_name = queue_opts
      callback = create_subscription_callback(queue_name, amqp_queue_name, handler, opts)
      keys = opts.slice(*SUBSCRIPTION_KEYS).merge(:key => "#", :ack => true)
      logger.debug "Beetle: subscribing to queue #{amqp_queue_name} with key # on server #{@server}"
      queues[queue_name].subscribe(keys, &callback)
      subscriptions[queue_name] = [keys, callback]
    end

    def pause(queue_name)
      return unless queues[queue_name].subscribed?
      queues[queue_name].unsubscribe
    end

    def resume(queue_name)
      return if queues[queue_name].subscribed?
      keys, callback = subscriptions[queue_name]
      queues[queue_name].subscribe(keys, &callback)
    end

    def create_subscription_callback(queue_name, amqp_queue_name, handler, opts)
      server = @server
      lambda do |header, data|
        if channel(server).closing?
          logger.info "Beetle: ignoring message since channel to server #{server} already closed"
          return
        end
        begin
          # logger.debug "Beetle: received message"
          processor = Handler.create(handler, opts)
          message_options = opts.merge(:server => server, :store => @client.deduplication_store)
          m = Message.new(amqp_queue_name, header, data, message_options)
          result = m.process(processor)
          if result.reject?
            if @client.config.dead_lettering_enabled?
              header.reject(:requeue => false)
            else
              sleep 1
              header.reject(:requeue => true)
            end
          elsif reply_to = header.attributes[:reply_to]
            # logger.info "Beetle: sending reply to queue #{reply_to}"
            # require 'ruby-debug'
            # Debugger.start
            # debugger
            status = result == Beetle::RC::OK ? "OK" : "FAILED"
            exchange = AMQP::Exchange.new(channel(server), :direct, "")
            exchange.publish(m.handler_result.to_s, :routing_key => reply_to, :persistent => false, :headers => {:status => status})
          end
          # logger.debug "Beetle: processed message"
        rescue Exception
          Beetle::reraise_expectation_errors!
          # swallow all exceptions
          logger.error "Beetle: internal error during message processing: #{$!}: #{$!.backtrace.join("\n")}"
        ensure
          # processing_completed swallows all exceptions, so we don't need to protect this call
          processor.processing_completed
        end
      end
    end

    def create_exchange!(name, opts)
      channel.__send__(opts[:type], name, opts.slice(*EXCHANGE_CREATION_KEYS))
    end

    def bind_queue!(queue_name, creation_keys, exchange_name, binding_keys)
      queue = channel.queue(queue_name, creation_keys)
      target_servers = @client.servers + @client.additional_subscription_servers
      @dead_lettering.bind_dead_letter_queues!(channel, target_servers, queue_name, creation_keys)
      exchange = exchange(exchange_name)
      queue.bind(exchange, binding_keys)
      queue
    end

    def connection_settings
      {
        :host => current_host, :port => current_port, :logging => false,
        :user => @client.config.user, :pass => @client.config.password, :vhost => @client.config.vhost,
        :on_tcp_connection_failure => on_tcp_connection_failure
      }
    end

    def on_tcp_connection_failure
      Proc.new do |settings|
        logger.warn "Beetle: connection failed: #{server_from_settings(settings)}"
        EM::Timer.new(10) { connect_server(settings) }
      end
    end

    def on_tcp_connection_loss(connection, settings)
      # reconnect in 10 seconds, without enforcement
      logger.warn "Beetle: lost connection: #{server_from_settings(settings)}. reconnecting."
      connection.reconnect(false, 10)
    end

    def connect_server(settings)
      server = server_from_settings settings
      logger.info "Beetle: connecting to rabbit #{server}"
      AMQP.connect(settings) do |connection|
        connection.on_tcp_connection_loss(&method(:on_tcp_connection_loss))
        @connections[server] = connection
        open_channel_and_subscribe(connection, settings)
      end
    rescue EventMachine::ConnectionError => e
      # something serious went wrong, for example DNS lookup failure
      # in this case, the on_tcp_connection_failure callback is never called automatically
      logger.error "Beetle: connection failed: #{e.class}(#{e})"
      settings[:on_tcp_connection_failure].call(settings)
    end

    def open_channel_and_subscribe(connection, settings)
      server = server_from_settings settings
      AMQP::Channel.new(connection) do |channel|
        channel.prefetch(@client.config.prefetch_count)
        channel.auto_recovery = true
        set_current_server server
        @channels[server] = channel
        create_exchanges(@exchanges_for_queues)
        bind_queues(@listened_queues)
        subscribe_queues(@listened_queues)
      end
    end
  end
end
