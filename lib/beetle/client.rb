module Beetle
  # This class provides the interface through which messaging is configured for both
  # message producers and consumers. It keeps references to an instance of a
  # Beetle::Subscriber, a Beetle::Publisher (both of which are instantiated on demand),
  # and a reference to an instance of Beetle::DeduplicationStore.
  #
  # Configuration of exchanges, queues, messages, and message handlers is done by calls to
  # corresponding register_ methods. Note that these methods just build up the
  # configuration, they don't interact with the AMQP servers.
  #
  # On the publisher side, publishing a message will ensure that the exchange it will be
  # sent to, and each of the queues bound to the exchange, will be created on demand. On
  # the subscriber side, exchanges, queues, bindings and queue subscriptions will be
  # created when the application calls the listen method. An application can decide to
  # subscribe to only a subset of the configured queues by passing a list of queue names
  # to the listen method.
  #
  # The net effect of this strategy is that producers and consumers can be started in any
  # order, so that no message is lost if message producers are accidentally started before
  # the corresponding consumers.
  class Client
    include Logging

    # the AMQP servers available for publishing
    attr_reader :servers

    # an options hash for the configured exchanges
    attr_reader :exchanges

    # an options hash for the configured queues
    attr_reader :queues

    # an options hash for the configured queue bindings
    attr_reader :bindings

    # an options hash for the configured messages
    attr_reader :messages

    # the deduplication store to use for this client
    attr_reader :deduplication_store

    # accessor for the beetle configuration
    attr_reader :config

    # create a fresh Client instance from a given configuration object
    def initialize(config = Beetle.config)
      @config  = config
      @servers = config.servers.split(/ *, */)
      @exchanges = {}
      @queues = {}
      @messages = {}
      @bindings = {}
      @deduplication_store = DeduplicationStore.new(config)
    end

    # register an exchange with the given _name_ and a set of _options_:
    # [<tt>:type</tt>]
    #   the type option will be overwritten and always be <tt>:topic</tt>, beetle does not allow fanout exchanges
    # [<tt>:durable</tt>]
    #   the durable option will be overwritten and always be true. this is done to ensure that exchanges are never deleted

    def register_exchange(name, options={})
      name = name.to_s
      raise ConfigurationError.new("exchange #{name} already configured") if exchanges.include?(name)
      exchanges[name] = options.symbolize_keys.merge(:type => :topic, :durable => true)
    end

    # register a durable, non passive, non auto_deleted queue with the given _name_ and an _options_ hash:
    # [<tt>:exchange</tt>]
    #   the name of the exchange this queue will be bound to (defaults to the name of the queue)
    # [<tt>:key</tt>]
    #   the binding key (defaults to the name of the queue)
    # automatically registers the specified exchange if it hasn't been registered yet

    def register_queue(name, options={})
      name = name.to_s
      raise ConfigurationError.new("queue #{name} already configured") if queues.include?(name)
      opts = {:exchange => name, :key => name, :auto_delete => false, :amqp_name => name}.merge!(options.symbolize_keys)
      opts.merge! :durable => true, :passive => false, :exclusive => false
      exchange = opts.delete(:exchange).to_s
      key = opts.delete(:key)
      queues[name] = opts
      register_binding(name, :exchange => exchange, :key => key)
    end

    # register an additional binding for an already configured queue _name_ and an _options_ hash:
    # [<tt>:exchange</tt>]
    #   the name of the exchange this queue will be bound to (defaults to the name of the queue)
    # [<tt>:key</tt>]
    #   the binding key (defaults to the name of the queue)
    # automatically registers the specified exchange if it hasn't been registered yet

    def register_binding(queue_name, options={})
      name = queue_name.to_s
      opts = options.symbolize_keys
      exchange = (opts[:exchange] || name).to_s
      key = (opts[:key] || name).to_s
      (bindings[name] ||= []) << {:exchange => exchange, :key => key}
      register_exchange(exchange) unless exchanges.include?(exchange)
      queues = (exchanges[exchange][:queues] ||= [])
      queues << name unless queues.include?(name)
    end

    # register a persistent message with a given _name_ and an _options_ hash:
    # [<tt>:key</tt>]
    #   specifies the routing key for message publishing (defaults to the name of the message)
    # [<tt>:ttl</tt>]
    #   specifies the time interval after which the message will be silently dropped (seconds).
    #   defaults to Message::DEFAULT_TTL.
    # [<tt>:redundant</tt>]
    #   specifies whether the message should be published redundantly (defaults to false)

    def register_message(message_name, options={})
      name = message_name.to_s
      raise ConfigurationError.new("message #{name} already configured") if messages.include?(name)
      opts = {:exchange => name, :key => name}.merge!(options.symbolize_keys)
      opts.merge! :persistent => true
      opts[:exchange] = opts[:exchange].to_s
      messages[name] = opts
    end

    # registers a handler for a list of queues (which must have been registered
    # previously). The handler will be invoked when any messages arrive on the queue.
    #
    # Examples:
    #   register_handler([:foo, :bar], :timeout => 10.seconds) { |message| puts "received #{message}" }
    #
    #   on_error   = lambda{ puts "something went wrong with baz" }
    #   on_failure = lambda{ puts "baz has finally failed" }
    #
    #   register_handler(:baz, :exceptions => 1, :errback => on_error, :failback => on_failure) { puts "received baz" }
    #
    #   register_handler(:bar, BarHandler)
    #
    # For details on handler classes see class Beetle::Handler

    def register_handler(queues, *args, &block)
      queues = Array(queues).map(&:to_s)
      queues.each {|q| raise UnknownQueue.new(q) unless self.queues.include?(q)}
      opts = args.last.is_a?(Hash) ? args.pop : {}
      handler = args.shift
      raise ArgumentError.new("too many arguments for handler registration") unless args.empty?
      subscriber.register_handler(queues, opts, handler, &block)
    end

    # this is a convenience method to configure exchanges, queues, messages and handlers
    # with a common set of options. allows one to call all register methods without the
    # register_ prefix. returns self.
    #
    # Example:
    #  client = Beetle.client.new.configure :exchange => :foobar do |config|
    #    config.queue :q1, :key => "foo"
    #    config.queue :q2, :key => "bar"
    #    config.message :foo
    #    config.message :bar
    #    config.handler :q1 { puts "got foo"}
    #    config.handler :q2 { puts "got bar"}
    #  end
    def configure(options={}) #:yields: config
      yield Configurator.new(self, options)
      self
    end

    # publishes a message. the given options hash is merged with options given on message registration.
    def publish(message_name, data=nil, opts={})
      message_name = message_name.to_s
      raise UnknownMessage.new("unknown message #{message_name}") unless messages.include?(message_name)
      publisher.publish(message_name, data, opts)
    end

    # sends the given message to one of the configured servers and returns the result of running the associated handler.
    #
    # unexpected behavior can ensue if the message gets routed to more than one recipient, so be careful.
    def rpc(message_name, data=nil, opts={})
      message_name = message_name.to_s
      raise UnknownMessage.new("unknown message #{message_name}") unless messages.include?(message_name)
      publisher.rpc(message_name, data, opts)
    end

    # purges the given queue on all configured servers
    def purge(queue_name)
      queue_name = queue_name.to_s
      raise UnknownQueue.new("unknown queue #{queue_name}") unless queues.include?(queue_name)
      publisher.purge(queue_name)
    end

    # start listening to a list of messages (default to all registered messages).
    # runs the given block before entering the eventmachine loop.
    def listen(messages=self.messages.keys, &block)
      messages = messages.map(&:to_s)
      messages.each{|m| raise UnknownMessage.new("unknown message #{m}") unless self.messages.include?(m)}
      subscriber.listen(messages, &block)
    end

    # stops the eventmachine loop
    def stop_listening
      subscriber.stop!
    end

    # disconnects the publisher from all servers it's currently connected to
    def stop_publishing
      publisher.stop
    end

    # traces messages without consuming them. useful for debugging message flow.
    def trace(messages=self.messages.keys, &block)
      queues.each do |name, opts|
        opts.merge! :durable => false, :auto_delete => true, :amqp_name => queue_name_for_tracing(opts[:amqp_name])
      end
      register_handler(queues.keys) do |msg|
        puts "-----===== new message =====-----"
        puts "SERVER: #{msg.server}"
        puts "HEADER: #{msg.header.inspect}"
        puts "MSGID: #{msg.msg_id}"
        puts "DATA: #{msg.data}"
      end
      listen(messages, &block)
    end

    # evaluate the ruby files matching the given +glob+ pattern in the context of the client instance.
    def load(glob)
      b = binding
      Dir[glob].each do |f|
        eval(File.read(f), b, f)
      end
    end

    private

    class Configurator #:nodoc:all
      def initialize(client, options={})
        @client = client
        @options = options
      end
      def method_missing(method, *args, &block)
        super unless %w(exchange queue binding message handler).include?(method.to_s)
        options = @options.merge(args.last.is_a?(Hash) ? args.pop : {})
        @client.send("register_#{method}", *(args+[options]), &block)
      end
    end

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
