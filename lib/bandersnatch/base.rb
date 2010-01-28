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

    def initialize(options = {})
      @options = options
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

    def mq
      @mqs[@server] ||= MQ.new(amqp_connection)
    end

    def stop
      stop!
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
      exchanges_for_current_server[name] = create_exchange!(name, opts)
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
      queues[name] = bind_queue!(queue_name, creation_keys, exchange_name, binding_keys)
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
