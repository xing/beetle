module Beetle
  class Subscriber < Base

    attr_accessor :handlers

    EXCHANGE_CREATION_KEYS  = [:auto_delete, :durable, :internal, :nowait, :passive]
    RECOVER_AFTER           = 10.seconds

    def initialize(client, options = {})
      super
      @handlers = {}
      @amqp_connections = {}
      @mqs = {}
    end

    def listen(messages=@messages.keys)
      EM.run do
        create_exchanges(messages)
        bind_queues(messages)
        subscribe(messages)
      end
    end

    def register_handler(messages, opts, handler=nil, &block)
      Array(messages).each do |message|
        (@handlers[message] ||= []) << [opts.symbolize_keys, Handler.create(handler || block, opts)]
      end
    end

    private

    def subscribe(messages=nil)
      messages ||= @messages.keys
      Array(messages).each do |message|
        @servers.each do |s|
          set_current_server s
          subscribe_message(message)
        end
      end
    end

    def queues_with_handlers(messages)
      messages.map { |name| @handlers[name].map {|opts, _| opts[:queue] || name } }.flatten
    end

    def mq(server=@server)
      @mqs[server] ||= MQ.new(amqp_connection)
    end

    def subscribe_message(message)
      handlers = Array(@handlers[message])
      error("no handler for message #{message}") if handlers.empty?
      handlers.each do |opts, handler|
        opts = opts.dup
        key = opts.delete(:key) || message
        queue = opts.delete(:queue) || message
        callback = create_subscription_callback(@server, queue, handler)
        logger.debug "subscribing to queue #{queue} with key #{key} for message #{message}"
        begin
          queues[queue].subscribe(opts.merge(:key => "#{key}.#"), &callback)
        rescue MQ::Error
          error("Binding multiple handlers for the same queue isn't possible. You might want to use the :queue option")
        end
      end
    end

    def create_subscription_callback(server, queue, handler)
      lambda do |header,data|
        begin
          m = Message.new(queue, header, data)
          m.server = server
          m.process(handler)
        rescue Exception => e
          handler.process_exception e
          logger.error "Error during message processing. Message will get redelivered. #{m}\n #{e}"
          install_recovery_timer(server)
        end
      end
    end

    def install_recovery_timer(server)
      @timer.cancel if @timer
      @timer = EM::Timer.new(RECOVER_AFTER) do
        logger.info "Redelivering unacked messages that could not be verified because of unavailable Redis"
        mq(server).recover(true)
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

    def new_amqp_connection
      # FIXME: wtf, how to test that reconnection feature....
      con = AMQP.connect(:host => current_host, :port => current_port)
      con.instance_variable_set("@on_disconnect", proc{ con.__send__(:reconnect) })
      con
    end

    def amqp_connection
      @amqp_connections[@server] ||= new_amqp_connection
    end
  end
end
