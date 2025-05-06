require 'json'

module Beetle
  # Abstract base class shared by Publisher and Subscriber
  class Base
    include Logging

    attr_accessor :options, :servers, :server  #:nodoc:

    def initialize(client, options = {}) #:nodoc:
      @options = options
      @client = client
      @servers = @client.servers.clone
      @server = @servers[rand @servers.size]
      @exchanges = {}
      @queues = {}
    end

    private

    def error(text)
      logger.error text
      raise Error.new(text)
    end

    def current_host
      @server.split(':').first
    end

    def current_port
      @server =~ /:(\d+)$/ ? $1.to_i : 5672
    end


    def connection_options_for_server(server)
      @client.config.connection_options_for_server(server)
    end

    def set_current_server(s)
      @server = s
    end

    def server_from_settings(settings)
      settings.values_at(:host,:port).join(':')
    end

    def each_server
      @servers.each { |s| set_current_server(s); yield }
    end

    def each_server_sorted_randomly
      @servers.sort_by{rand}.each { |s| set_current_server(s); yield }
    end

    def exchanges
      @exchanges[@server] ||= {}
    end

    def exchange(name)
      exchanges[name] ||= create_exchange!(name, @client.exchanges[name])
    end

    def queues
      @queues[@server] ||= {}
    end

    def queue(name)
      queues[name] ||=
        begin
          opts = @client.queues[name]
          raise UnknownQueue.new("You are trying to bind a queue #{name} which is not configured!") unless opts
          logger.debug("Beetle: binding queue #{name} with internal name #{opts[:amqp_name]} on server #{@server}")
          queue_name = opts[:amqp_name]
          creation_options = opts.slice(*QUEUE_CREATION_KEYS)

          the_queue = declare_queue!(queue_name, creation_options)
          @client.bindings[name].each do |binding_options|
            exchange_name = binding_options[:exchange]
            binding_options = binding_options.slice(*QUEUE_BINDING_KEYS)
            logger.debug("Beetle: binding queue #{queue_name} to #{exchange_name} with opts: #{binding_options.inspect}")
            bind_queue!(the_queue, exchange_name, binding_options)
          end
          the_queue
        end
    end

    def bind_dead_letter_queue!(channel, target_queue, creation_options = {})
      policy_options = @client.queues[target_queue].slice(:dead_lettering, :lazy, :dead_lettering_msg_ttl)
      policy_options[:message_ttl] = policy_options.delete(:dead_lettering_msg_ttl)
      dead_letter_queue_name = "#{target_queue}_dead_letter"
      if policy_options[:dead_lettering]
        logger.debug("Beetle: creating dead letter queue #{dead_letter_queue_name} with opts: #{creation_options.inspect}")
        channel.queue(dead_letter_queue_name, creation_options.dup)
      end
      return {
        :queue_name => target_queue,
        :bindings => @client.bindings[target_queue],
        :dead_letter_queue_name => dead_letter_queue_name,
        :message_ttl => policy_options[:message_ttl]
      }.merge(policy_options)
    end

    # called by <tt>declare_queue!</tt>
    def publish_policy_options(options)
      # avoid endless recursion
      return if options[:queue_name] == @client.config.beetle_policy_updates_queue_name

      payload = options.merge(:server => @server)

      if @client.config.update_queue_properties_synchronously
        logger.debug("Beetle: updating policy options on #{@server}: #{payload.inspect}")
        @client.update_queue_properties!(payload)
      else
        logger.debug("Beetle: publishing policy options on #{@server}: #{payload.inspect}")
        # make sure to declare the queue, so the message does not get lost
        ActiveSupport::Notifications.instrument('publish.beetle') do
          queue(@client.config.beetle_policy_updates_queue_name)
          data = payload.to_json
          opts = Message.publishing_options(:key => @client.config.beetle_policy_updates_routing_key, :persistent => true, :redundant => false)
          exchange(@client.config.beetle_policy_exchange_name).publish(data, opts.dup)
        end
      end
    end

  end
end
