require 'net/http'
require 'json'

module Beetle
  class DeadLettering
    class FailedRabbitRequest < StandardError; end

    def initialize(config)
      @config = config
    end

    def bind_dead_letter_queues!(channel, servers, target_queue, creation_keys = {})
      if @config.dead_lettering_enabled?
        dead_letter_queue_name = dead_letter_queue_name(target_queue)
        logger.info("Beetle: creating dead letter queue #{dead_letter_queue_name} with opts: #{creation_keys.inspect}")
        channel.queue(dead_letter_queue_name, creation_keys)
      end

      if @config.dead_lettering_enabled?
        logger.info("Beetle: setting #{dead_letter_queue_name} as dead letter queue of #{target_queue} on all servers")
      end
      set_queue_policies!(servers, target_queue)

      if @config.dead_lettering_enabled?
        logger.info("Beetle: setting #{target_queue} as dead letter queue of #{dead_letter_queue_name} on all servers")
        set_queue_policies!(
          servers,
          dead_letter_queue_name,
          :message_ttl => @config.dead_lettering_msg_ttl,
          :routing_key => target_queue
        )
      end
    end

    def set_queue_policies!(servers, queue_name, options={})
      servers.each { |server| set_queue_policy!(server, queue_name, options) }
    end

    def set_queue_policy!(server, queue_name, options={})
      raise ArgumentError.new("server missing")     if server.blank?
      raise ArgumentError.new("queue name missing") if queue_name.blank?

      return unless @config.dead_lettering_enabled? || @config.lazy_queues_enabled?

      vhost = CGI.escape(@config.vhost)
      request_url = URI("http://#{server}/api/policies/#{vhost}/#{queue_name}_policy")
      request = Net::HTTP::Put.new(request_url)

      # set up queue policy
      definition = {}
      if @config.dead_lettering_enabled?
        definition["dead-letter-routing-key"] = dead_letter_routing_key(queue_name, options)
        definition["dead-letter-exchange"] = ""
        definition["message-ttl"] = options[:message_ttl] if options[:message_ttl]
      end

      definition["queue-mode"] = "lazy" if @config.lazy_queues_enabled?

      request_body = {
        "pattern" => "^#{queue_name}$",
        "priority" => 1,
        "apply-to" => "queues",
        "definition" => definition,
      }

      response = run_rabbit_http_request(request_url, request) do |http|
        http.request(request, request_body.to_json)
      end

      unless %w(200 201 204).include?(response.code)
        log_error("Failed to create policy for queue #{queue_name}", response)
        raise FailedRabbitRequest.new("Could not create policy")
      end

      :ok
    end

    def dead_letter_routing_key(queue_name, options)
      options.fetch(:routing_key) { dead_letter_queue_name(queue_name) }
    end

    def dead_letter_queue_name(queue_name)
      "#{queue_name}_dead_letter"
    end

    def run_rabbit_http_request(uri, request, &block)
      request.basic_auth(@config.user, @config.password)
      request["Content-Type"] = "application/json"
      Net::HTTP.start(uri.hostname, @config.api_port, :read_timeout => @config.dead_lettering_read_timeout) do |http|
        block.call(http) if block_given?
      end
    end

    def log_error(msg, response)
      logger.error(msg)
      logger.error("Response code was #{response.code}")
      logger.error(response.body)
    end

    def logger
      @config.logger
    end
  end
end
