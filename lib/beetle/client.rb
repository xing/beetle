require 'json'

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
  # created when the application calls the listen_queues method. An application can decide
  # to subscribe to only a subset of the configured queues by passing a list of queue
  # names to the listen method.
  #
  # The net effect of this strategy is that producers and consumers can be started in any
  # order, so that no message is lost if message producers are accidentally started before
  # the corresponding consumers.
  class Client
    include Logging

    # the AMQP servers available for publishing
    attr_reader :servers

    # additional AMQP servers available for subscribing. useful for migration scenarios.
    attr_reader :additional_subscription_servers

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
      @exchanges = {}
      @queues = {}
      @messages = {}
      @bindings = {}
      @deduplication_store = DeduplicationStore.new(config)
      @queue_properties = QueueProperties.new(config)
      load_brokers_from_config
      register_exchange(config.beetle_policy_exchange_name)
      # make sure dead lettering is false for the policy update queue
      register_queue(
        config.beetle_policy_updates_queue_name,
        :exchange => config.beetle_policy_exchange_name,
        :key => config.beetle_policy_updates_routing_key,
        :dead_lettering => false,
        :lazy => false,
      )
    end

    def single_broker_mode?
      servers.size == 1
    end

    # register an exchange with the given _name_ and a set of _options_:
    # [<tt>:type</tt>]
    #   the type option will be overwritten and always be <tt>:topic</tt>, beetle does not allow fanout exchanges
    # [<tt>:durable</tt>]
    #   the durable option will be overwritten and always be true. this is done to ensure that exchanges are never deleted

    def register_exchange(name, options={})
      name = name.to_s
      raise ConfigurationError.new("exchange #{name} already configured") if exchanges.include?(name)
      exchanges[name] = options.symbolize_keys.merge(:type => :topic, :durable => true, :queues => [])
    end

    # register a durable, non passive, non auto_deleted queue with the given _name_ and an _options_ hash:
    # [<tt>:exchange</tt>]
    #   the name of the exchange this queue will be bound to (defaults to the name of the queue)
    # [<tt>:key</tt>]
    #   the binding key (defaults to the name of the queue)
    # [<tt>:lazy</tt>]
    #   whether the queue should use lazy mode (defaults to <tt>config.lazy_queues_enabled</tt>)
    # [<tt>:dead_lettering</tt>]
    #   whether the queue should use dead lettering (defaults to <tt>config.dead_lettering_enabled</tt>)
    # automatically registers the specified exchange if it hasn't been registered yet

    def register_queue(name, options={})
      name = name.to_s
      raise ConfigurationError.new("queue #{name} already configured") if queues.include?(name)
      opts = {
        :exchange => name, :key => name, :auto_delete => false, :amqp_name => name,
        :lazy => config.lazy_queues_enabled, :dead_lettering => config.dead_lettering_enabled,
        :dead_lettering_msg_ttl => config.dead_lettering_msg_ttl
      }.merge!(options.symbolize_keys)
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
      queues = exchanges[exchange][:queues]
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
      exchange = opts[:exchange] = opts[:exchange].to_s
      register_exchange(exchange) unless exchanges.include?(exchange)
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
      queues = determine_queue_names(Array(queues))
      opts = args.last.is_a?(Hash) ? args.pop : {}
      handler = args.shift
      raise ArgumentError.new("too many arguments for handler registration") unless args.empty?
      subscriber.register_handler(queues, opts, handler, &block)
    end

    # this is a convenience method to configure exchanges, queues, messages and handlers
    # with a common set of options. allows one to call all register methods without the
    # register_ prefix. returns self. if the passed in block has no parameters, the block
    # will be evaluated in the context of the client configurator.
    #
    # Example: (block with config argument)
    #  client = Beetle.client.new.configure :exchange => :foobar do |config|
    #    config.queue :q1, :key => "foo"
    #    config.queue :q2, :key => "bar"
    #    config.message :foo
    #    config.message :bar
    #    config.handler :q1 { puts "got foo"}
    #    config.handler :q2 { puts "got bar"}
    #  end
    #
    # Example: (block without config argument)
    #  client = Beetle.client.new.configure :exchange => :foobar do
    #    queue :q1, :key => "foo"
    #    queue :q2, :key => "bar"
    #    message :foo
    #    message :bar
    #    handler :q1 { puts "got foo"}
    #    handler :q2 { puts "got bar"}
    #  end
    #
    def configure(options={}, &block)
      configurator = Configurator.new(self, options)
      if block.arity == 1
        yield configurator
      else
        configurator.instance_eval(&block)
      end
      self
    end

    # publishes a message. the given options hash is merged with options given on message registration.
    # WARNING: empty message bodies can lead to problems.
    def publish(message_name, data=nil, opts={})
      message_name = validated_message_name(message_name)
      publisher.publish(message_name, data, opts)
    end

    # purges the given queues on all configured servers
    def purge(*queues)
      queues = determine_queue_names(queues)
      publisher.purge(queues)
    end

    # start listening to all registered queues. Calls #listen_queues internally
    # runs the given block before entering the eventmachine loop.
    def listen(_deprecated_messages=nil, &block)
      raise Error.new("Beetle::Client#listen no longer works with arguments. Please use #listen_queues(['queue1', 'queue2']) instead") if _deprecated_messages
      listen_queues(&block)
    end

    # start listening to a list of queues (default to all registered queues).
    # runs the given block before entering the eventmachine loop.
    def listen_queues(*queues, &block)
      queues = determine_queue_names(queues)
      subscriber.listen_queues(queues, &block)
    end

    # stops the subscriber by closing all channels and connections. note this an
    # asynchronous operation due to the underlying eventmachine mechanism.
    def stop_listening
      @subscriber.stop! if @subscriber
    end

    # disconnects the publisher from all servers it's currently connected to
    def stop_publishing
      @publisher.stop if @publisher
    end

    # pause listening on a list of queues
    def pause_listening(*queues)
      queues = determine_queue_names(queues)
      subscriber.pause_listening(queues)
    end

    # resume listening on a list of queues
    def resume_listening(*queues)
      queues = determine_queue_names(queues)
      subscriber.resume_listening(queues)
    end

    # throttle publishing of messages based on queue lengths.
    #
    #    client.throttle(:foo => 10000, :bar => 10_000)
    #
    # throttle publisher to 1 message per second as long as queue foo has more
    # than 10000 entries or queue bar has more than 100000 entries across all
    # servers. Queue lenghts are periodically determined during publishing. You
    # only want to use this feature if you plan to publish a huge amount of
    # messages to slow consumers so as to not overload the broker or the redis
    # deduplication store. You'll want to use this feature when running background
    # jobs that publish huge amounts of messages to avoid overloading brokers
    # and the message deduplication store.
    def throttle(throttling_options)
      publisher.throttle(throttling_options.stringify_keys)
    end

    # is the publisher currently throttled?
    def throttled?
      publisher.throttled?
    end

    # set up queues and policies for all configured queues. Otherwise this will
    # happen on first use of an exchange, which can be undesired for latency
    # sensitive endpoints. Only needs to be called once.
    def setup_queues_and_policies
      publisher.setup_queues_and_policies
    end

    # traces queues without consuming them. useful for debugging message flow.
    def trace(queue_names=self.queues.keys, tracer=nil, &block)
      queues_to_trace = self.queues.slice(*queue_names)
      queues_to_trace.each do |name, opts|
        opts.merge! :durable => false, :auto_delete => true, :amqp_name => queue_name_for_tracing(opts[:amqp_name])
      end
      tracer ||=
        lambda do |msg|
          puts "-----===== new message =====-----"
          puts "SERVER: #{msg.server}"
          puts "HEADER: #{msg.header.attributes[:headers].inspect}"
          puts "EXCHANGE: #{msg.header.method.exchange}"
          puts "KEY: #{msg.header.method.routing_key}"
          puts "MSGID: #{msg.msg_id}"
          puts "DATA: #{msg.data}"
        end
      register_handler(queue_names){|msg| tracer.call msg }
      @subscriber.tracing = true
      listen_queues(queue_names, &block)
      @subscriber.tracing = false
    end

    # evaluate the ruby files matching the given +glob+ pattern in the context of the client instance.
    def load(glob)
      b = binding
      Dir[glob].each do |f|
        eval(File.read(f), b, f)
      end
    end

    def reset
      stop_publishing
      stop_listening
      config.reload
      load_brokers_from_config
    rescue Exception => e
      logger.warn("Error resetting client")
      logger.warn(e)
    ensure
      @publisher = nil
      @subscriber = nil
    end

    def update_queue_properties!(message_payload, &block)
      @queue_properties.update_queue_properties!(message_payload, &block)
    end

    private

    def determine_queue_names(queues)
      if queues.empty?
        self.queues.keys
      else
        queues.flatten.map{|q| validated_queue_name(q)}
      end
    end

    def validated_queue_name(queue_name)
      queue_name = queue_name.to_s
      raise UnknownQueue.new("unknown queue #{queue_name}") unless queues.include?(queue_name)
      queue_name
    end

    def validated_message_name(message_name)
      message_name = message_name.to_s
      raise UnknownMessage.new("unknown message #{message_name}") unless messages.include?(message_name)
      message_name
    end

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
      # need to override binding explicitely
      def binding(*args, &block)
        method_missing(:binding, *args, &block)
      end
    end

    def publisher
      @publisher ||= Publisher.new(self)
    end

    def subscriber
      @subscriber ||= Subscriber.new(self)
    end

    def queue_name_for_tracing(queue)
      "trace-#{queue}-#{Beetle.hostname}"
    end

    def load_brokers_from_config
      @servers = parse_server_list(config.servers)
      @additional_subscription_servers = parse_server_list(config.additional_subscription_servers) - @servers
    end

    def parse_server_list(s)
      s.split(/ *, */).uniq.reject(&:blank?)
    end
  end
end
