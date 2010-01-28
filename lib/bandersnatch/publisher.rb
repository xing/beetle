module Bandersnatch
  class Publisher < Base
    PUBLISHING_KEYS = [:key, :mandatory, :immediate, :persistent]

    def initialize(servers)
      super
      @dead_servers = {}
      @bunnies = {}
    end

    def test
      error "testing only allowed in development environment" unless RAILS_ENV=="development"
      trap("INT") { exit(1) }
      while true
        publish "redundant", "hello, I'm redundant!"
        sleep 1
      end
    end

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

    def bunny
      @bunnies[@server] ||= new_bunny
    end

    def new_bunny
      b = Bunny.new(:host => current_host, :port => current_port, :logging => !!@options[:logging])
      b.start
      b
    end

    def publish_with_failover(exchange_name, message_name, data, opts)
      tries = @servers.size
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
        stop!
        mark_server_dead
        tries -= 1
        retry if tries > 0
        logger.error "failed to send message!"
        error("message could not be delivered: #{message_name}")
      end
      published
    end

    def publish_with_redundancy(exchange_name, message_name, data, opts)
      if @servers.size < 2
        logger.error "at least two active servers are required for redundant publishing"
        return publish_with_failover(exchange_name, message_name, data, opts)
      end
      published = 0
      data = Message.encode(data, :with_uuid => true, :ttl => opts[:ttl])
      loop do
        break if published == 2 || @servers.size < 2
        begin
          select_next_server
          logger.debug "trying to send #{message_name} to #{@server}"
          exchange(exchange_name).publish(data, opts.slice(*PUBLISHING_KEYS))
          published += 1
          logger.debug "message sent (#{published})!"
        rescue Bunny::ServerDownError, Bunny::ConnectionError
          stop!
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

    private
    def recycle_dead_servers
      recycle = []
      @dead_servers.each do |s, dead_since|
        recycle << s if dead_since < 10.seconds.ago
      end
      @servers.concat recycle
      logger.debug "servers #{@servers.inspect}"
      recycle.each {|s| @dead_servers.delete(s)}
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

    def create_exchange!(name, opts)
      bunny.exchange(name, opts)
    end

    # TODO: Refactor, fethch the keys and stuff itself
    def bind_queue!(queue_name, creation_keys, exchange_name, binding_keys)
      queue = bunny.queue(queue_name, creation_keys)
      queue.bind(exchange(exchange_name), binding_keys)
      queue
    end

    def stop!
      begin
        bunny.stop
      rescue Exception
      end
      @bunnies[@server] = nil
      @exchanges[@server] = {}
    end
  end
end