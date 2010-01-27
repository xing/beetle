module Bandersnatch
  class Error < StandardError; end
  #
  # TODO TODO TODO FIXME
  # Refactorings incomming.
  # * extract to publisher and subscriber base classes
  # * only keep the neccassary code in Base
  class Base

    RECOVER_AFTER = 10.seconds

    attr_accessor :options, :amqp_config, :exchanges, :queues, :handlers, :messages, :servers, :server, :mode

    def initialize(mode, options = {})
      @options = options
      @mode = mode.to_sym
      error("Bandersnatch: unknown mode '#{mode}'. shoud be :pub or :sub") unless [:pub, :sub].include?(@mode)
      @exchanges = {}
      @queues = {}
      @handlers = {}
      @messages = {}
      @bunnies = {}
      @amqp_connections = {}
      @mqs = {}
      @trace = false
      @dead_servers = {}
      load_config(@options[:config_file])
    end

    def error(text)
      logger.error text
      raise Error.new(text)
    end

    def load_config(file_name=nil)
      file_name ||= Bandersnatch.config.config_file
      @amqp_config = YAML::load(ERB.new(IO.read(file_name)).result)
      @servers = @amqp_config[RAILS_ENV]['hostname'].split(/ *, */)
      @server = @servers[rand @servers.size]
      @messages = @amqp_config['messages']
    end

    def current_host
      @server.split(':').first
    end

    def current_port
      @server =~ /:(\d+)$/ ? $1.to_i : 5672
    end

    def set_current_server(s)
      @server = s
    end

    def mark_server_dead
      logger.info "server #{@server} down: #{$!}"
      @dead_servers[@server] = Time.now
      @servers.delete @server
      @server = @servers[rand @servers.size]
    end

    def select_next_server
      set_current_server(@servers[(@servers.index(@server)+1) % @servers.size])
    end

    def recycle_dead_servers
      recycle = []
      @dead_servers.each do |s, dead_since|
        recycle << s if dead_since < 10.seconds.ago
      end
      @servers.concat recycle
      logger.debug "servers #{@servers.inspect}"
      recycle.each {|s| @dead_servers.delete(s)}
    end

    def bunny
      @bunnies[@server] ||= new_bunny
    end

    def new_bunny
      b = Bunny.new(:host => current_host, :port => current_port, :logging => !!@options[:logging])
      b.start
      b
    end

    def amqp_connection
      @amqp_connections[@server] ||= new_amqp_connection
    end

    def new_amqp_connection
      AMQP.connect(:host => current_host, :port => current_port)
    end

    def mq
      @mqs[@server] ||= MQ.new(amqp_connection)
    end

    def stop_bunny
      begin
        bunny.stop
      rescue Exception
      end
      @bunnies[@server] = nil
      @exchanges[@server] = {}
    end

    # maybe this should be a callback
    def stop_amqp
      @amqp_connections.each_value{|c| c.close}
      @amqp_connections = {}
      @mqs = {}
      EM.stop_event_loop
    end

    def register_exchange(name, opts)
      @amqp_config["exchanges"][name] = opts.symbolize_keys
    end

    def register_queue(name, opts)
      @amqp_config["queues"][name] = opts.symbolize_keys
    end

    def register_handler(messages, opts, &block)
      Array(messages).each do |message|
        (@handlers[message] ||= []) << [opts.symbolize_keys, block]
      end
    end

    def exchanges_for_current_server
      @exchanges[@server] ||= {}
    end

    def exchange(name)
      create_exchange(name) unless exchange_exists?(name)
      exchanges_for_current_server[name]
    end

    def exchange_exists?(name)
      exchanges_for_current_server.include?(name)
    end

    def create_exchanges(messages)
      servers.each do |s|
        set_current_server s
        messages.each do |name|
          create_exchange(name)
        end
      end
    end

    EXCHANGE_CREATION_KEYS = [:auto_delete, :durable, :internal, :nowait, :passive]

    def create_exchange(name)
      opts = @amqp_config["exchanges"][name].symbolize_keys
      opts[:type] = opts[:type].to_sym
      case @mode
      when :pub
        exchanges_for_current_server[name] = bunny.exchange(name, opts)
      when :sub
        exchanges_for_current_server[name] = mq.__send__(opts[:type], name, opts.slice(*EXCHANGE_CREATION_KEYS))
      end
    end

    def bind_queues(messages)
      servers.each do |s|
        set_current_server s
        queues_with_handlers(messages).each do |name|
          bind_queue(name)
        end
      end
    end

    def queues_with_handlers(messages)
      messages.map do |name|
        @handlers[name].map {|opts, _| opts[:queue] || name }
      end.flatten
    end

    def queues
      @queues[@server] ||= {}
    end

    QUEUE_CREATION_KEYS = [:passive, :durable, :exclusive, :auto_delete, :no_wait]
    QUEUE_BINDING_KEYS = [:key, :no_wait]

    def bind_queue(name)
      logger.debug("Binding #{name}")
      opts = @amqp_config["queues"][name].dup
      opts.symbolize_keys!
      exchange_name = opts.delete(:exchange) || name
      queue_name = name
      if @trace
        opts.merge!(:durable => true, :auto_delete => true)
        queue_name = "trace-#{name}-#{`hostname`.chomp}"
      end
      binding_keys = opts.slice(*QUEUE_BINDING_KEYS)
      creation_keys = opts.slice(*QUEUE_CREATION_KEYS)
      case @mode
      when :pub
        queue = bunny.queue(queue_name, creation_keys)
        queue.bind(exchange(exchange_name), binding_keys)
      when :sub
        queue = mq.queue(queue_name, creation_keys)
        queue.bind(exchange(exchange_name), binding_keys)
      end
      queues[name] = queue
    end

    def subscribe(messages=nil)
      messages ||= @messages.keys
      Array(messages).each do |message|
        servers.each do |s|
          set_current_server s
          subscribe_message(message)
        end
      end
    end

    def subscribe_message(message)
      handlers = Array(@handlers[message])
      error("no handler for message #{message}") if handlers.empty?
      handlers.each do |opts, block|
        opts = opts.dup
        key = opts.delete(:key) || message
        queue = opts.delete(:queue) || message
        callback = create_subscription_callback(@server, queue, block)
        logger.debug "subscribing to queue #{queue} with key #{key} for message #{message}"
        begin
          queues[queue].subscribe(opts.merge(:key => "#{key}.#"), &callback)
        rescue MQ::Error
          error("Binding multiple handlers for the same queue isn't possible. You might want to use the :queue option")
        end
      end
    end

    def create_subscription_callback(server, queue, block)
      lambda do |header,data|
        begin
          message = Message.new(server, header, data)

          if message.expired?
            logger.warn "Message expired: #{message.uuid}"
          elsif message.insert_id(queue)
            begin
              block.call(message)
            rescue Exception
              logger.warn "Error during invocation of message handler for #{message}"
            end
          end

          header.ack
        rescue Exception
          logger.error "Error during message processing. Message will get redelivered. #{message}\n #{$!}"
          @timer.cancel if @timer
          @timer = EM::Timer.new(RECOVER_AFTER) do
            logger.info "Redelivering unacked messages that could not be verified because of unavailable Redis"
            @mqs[server].recover(true)
          end
        end
      end
    end

    PUBLISHING_KEYS = [:key, :mandatory, :immediate, :persistent]

    def publish(message_name, data, opts={})
      opts = (@messages[message_name]||{}).symbolize_keys.merge(opts.symbolize_keys)
      exchange_name = opts.delete(:exchange) || message_name
      recycle_dead_servers
      if opts[:redundant]
        publish_with_redundancy(exchange_name, message_name, data, opts)
      else
        publish_with_failover(exchange_name, message_name, data, opts)
      end
    end

    def publish_with_failover(exchange_name, message_name, data, opts)
      tries = servers.size
      logger.debug "sending #{message_name}"
      data = Message.encode(data, :ttl => opts[:ttl])
      published = 0
      begin
        select_next_server
        logger.debug "trying to send #{message_name} to #{@server}"
        exchange(exchange_name).publish(data, opts.slice(*PUBLISHING_KEYS))
        logger.debug "message sent!"
        published = 1
      rescue Bunny::ServerDownError, Bunny::ConnectionError
        stop_bunny
        mark_server_dead
        tries -= 1
        retry if tries > 0
        logger.error "failed to send message!"
        error("message could not be delivered: #{message_name}")
      end
      published
    end

    def publish_with_redundancy(exchange_name, message_name, data, opts)
      if servers.size < 2
        logger.error "at least two active servers are required for redundant publishing"
        return publish_with_failover(exchange_name, message_name, data, opts)
      end
      published = 0
      data = Message.encode(data, :with_uuid => true, :ttl => opts[:ttl])
      loop do
        break if published == 2 || servers.size < 2
        begin
          select_next_server
          logger.debug "trying to send #{message_name} to #{@server}"
          exchange(exchange_name).publish(data, opts.slice(*PUBLISHING_KEYS))
          published += 1
          logger.debug "message sent (#{published})!"
        rescue Bunny::ServerDownError, Bunny::ConnectionError
          stop_bunny
          mark_server_dead
        end
      end
      case published
      when 0
        error("message could not be delivered: #{message_name}")
      when 1
        logger.warn "failed to send message redundantly"
      end
      published
    end

    def listen(messages=@messages.keys)
      EM.run do
        yield if block_given?
        create_exchanges(messages)
        bind_queues(messages)
        subscribe
      end
    end

    def trace
      @trace = true
      listen do
        register_handler("redundant", :queue => "additional_queue", :ack => true, :key => '#') {|msg| puts "------===== Additional Handler =====-----" }
        register_handler(@messages.keys, :ack => true, :key => '#') do |msg|
          puts "-----===== new message =====-----"
          puts "SERVER: #{msg.server}"
          puts "HEADER: #{msg.header.inspect}"
          puts "UUID: #{msg.uuid}" if msg.uuid
          puts "DATA: #{msg.data}"
        end
      end
    end

    def test
      error "testing only allowed in development environment" unless RAILS_ENV=="development"
      trap("INT") { exit(1) }
      while true
        publish "redundant", "hello, I'm redundant!"
        sleep 1
      end
    end

    def can_do(modul, opts={})
      x = modul.underscore
      prefix = x.gsub('/','.')
      exchange = x.split('/')[1,-1].join('_')
      exchange = x if x.blank?
      abilities = opts.delete(:abilities) || :on_message
      register_exchange(exchange, :durable => true)
      register_queue(exchange, :durable => true)
      abilities.each do |a|
        message = "#{exchange}_#{a}"
        @messages[message] = {:persistent => true}
        register_handler(a, :ack => true, :key => "#{prefix}.#{a}.#") do |server, header, body|
          begin
            modul.send(a, header, body)
            header.ack if opts[:ack]
          rescue Exception
          end
        end
      end
    end

    def autoload(glob)
      Dir[glob + '/**/config/amqp_messaging.rb'].each do |f|
        eval(File.read f)
      end
    end

    private
      def logger
        self.class.logger
      end

      def self.logger
        Bandersnatch.config.logger
      end
  end
end
