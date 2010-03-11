module Beetle
  class Client
    attr_reader :servers, :exchanges, :queues, :messages

    # create a fresh Beetle::Client instance with the given options.
    # currently only one option is being honored:
    #   :servers => "host1:port1, host2:port2"
    # this overrides the default servers configured in Beetle.config.servers
    def initialize(options = {})
      @servers = (options[:servers] || Beetle.config.servers).split(/ *, */)
      @exchanges = {}
      @queues = {}
      @messages = {}
    end

    # register an exchange with the given _name_ and a set of options:
    # [<tt>:type</tt>]
    #   the type option will be overwritten and always be <tt>:topic</tt>, beetle does not allow fanout exchanges
    # [<tt>:durable</tt>]
    #   the durable option will be overwritten and always be true. this is done to ensure that exchanges are never deleted
    # returns the overwritten options
    def register_exchange(name, options={})
      raise ConfigurationError.new("exchange #{name} already configured") if exchanges.include?(name)
      exchanges[name] = options.symbolize_keys.merge(:type => :topic, :durable => true)
    end

    # passive: false       # amqp default is false
    # durable: true        # amqp default is false
    # exclusive: false     # amqp default is false
    # auto_delete: false   # amqp default is false
    # nowait: true         # amqp default is true
    # key: "#"             # listen to every message

    def register_queue(name, options={})
      raise ConfigurationError.new("queue #{name} already configured") if queues.include?(name)
      opts = {:exchange => name, :key => name}.merge!(options.symbolize_keys)
      opts.merge! :durable => true, :passive => false, :amqp_name => name
      queues[name] = opts
      exchange = opts[:exchange]
      register_exchange(exchange) unless exchanges.include?(exchange)
      (exchanges[exchange][:queues] ||= []) << name
    end

    # queue: "test"
    ### Spefify the queue for listeners (default is message name)
    # key: "test"
    ### Specifies the routing key pattern for message subscription.
    # ttl: <%= 1.hour %>
    ### Specifies the time interval after which messages are silently dropped (seconds)
    # mandatory: true
    ### default is false
    ### Tells the server how to react if the message
    ### cannot be routed to a queue. If set to _true_, the server will return an unroutable message
    ### with a Return method. If this flag is zero, the server silently drops the message.
    # immediate: false
    ### default is false
    ### Tells the server how to react if the message
    ### cannot be routed to a queue consumer immediately. If set to _true_, the server will return an
    ### undeliverable message with a Return method. If set to _false_, the server will queue the message,
    ### but with no guarantee that it will ever be consumed.
    # persistent: true
    ### default is false
    ### Tells the server whether to persist the message
    ### If set to _true_, the message will be persisted to disk and not lost if the server restarts.
    ### If set to _false_, the message will not be persisted across server restart. Setting to _true_
    ### incurs a performance penalty as there is an extra cost associated with disk access.

    def register_message(name, options={})
      raise ConfigurationError.new("message #{name} already configured") if messages.include?(name)
      opts = {:exchange => name, :key => name}.merge!(options.symbolize_keys)
      messages[name] = opts
    end

    # registers a handler for a list of messages (which must have been registered
    # previously). The handler will be invoked when any of the given messages arrive on
    # the scubscriber.
    #
    # Examples:
    #   register_handler(["foo", "bar"], :timeout => 10.seconds) { |message| puts "received #{message}" }
    #
    #   on_error   = lambda{ puts "something went wrong with baz" }
    #   on_failure = lambda{ puts "baz has finally failed" }
    #
    #   register_handler("baz", :exceptions => 1, :errback => on_error, :failback => on_failure) { puts "received baz" }
    #
    #   register_handler("bar", BarHandler)
    #
    # For details on handler classes see class Beetle::Handler
    #
    def register_handler(messages, *args, &block)
      Array(messages).each {|m| raise ConfigurationError.new("unknown message #{m}") unless self.messages.include?(m)}
      opts = args.last.is_a?(Hash) ? args.pop : {}
      handler = args.shift
      raise ArgumentError.new("too many arguments for handler registration") unless args.empty?
      subscriber.register_handler(messages, opts, handler, &block)
    end

    def publish(message_name, data=nil, opts={})
      publisher.publish(message_name, data, opts)
    end

    # sends the given message to one of the configured servers and returns the result of running the associated handler.
    # this will lead to unexpected behavior, if the message gets routed to more than one recipient, so be careful.
    def rpc(message_name, data=nil, opts={})
      publisher.rpc(message_name, data, opts)
    end

    # purges the given queue on all configured servers
    def purge(queue_name)
      publisher.purge(queue_name)
    end

    # start listening. runs the given block before entering the eventmachine loop.
    def listen(*args, &block)
      subscriber.listen(*args, &block)
    end

    # stops the eventmachine loop
    def stop_listening
      subscriber.stop!
    end

    # disconnects the publisher form all servers it's currently connected to
    def stop_publishing
      publisher.stop
    end

    # traces all messages received on all queues. useful for debugging message flow.
    def trace(&block)
      queues.each do |name, opts|
        opts.merge! :durable => false, :auto_delete => true, :amqp_name => queue_name_for_tracing(name)
      end
      register_handler(messages.keys) do |msg|
        puts "-----===== new message =====-----"
        puts "SERVER: #{msg.server}"
        puts "HEADER: #{msg.header.inspect}"
        puts "MSGID: #{msg.msg_id}"
        puts "DATA: #{msg.data}"
      end
      subscriber.listen &block
    end

    # evaluate the ruby files matching the given +glob+ pattern in the context of the client instance.
    def load(glob)
      b = binding
      Dir[glob].each do |f|
        eval(File.read(f), b, f)
      end
    end

    # returns the configured Logger instance
    def logger
      @logger ||= Beetle.config.logger
    end

    private

    def publisher
      @publisher ||= Publisher.new(self)
    end

    def subscriber
      @subscriber ||= Subscriber.new(self)
    end

    def queue_name_for_tracing(queue)
      "trace-#{queue}-#{`hostname`.chomp}-#{$$}"
    end
  end
end
