require 'net/http'
require 'json'

module Beetle
  class DeadLettering
    class FailedRabbitRequest < StandardError; end

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def set_queue_policies!(options)
      # logger.debug "Setting queue policies: #{options.inspect}"
      options = options.symbolize_keys
      server = options[:server]
      target_queue = options[:queue_name]
      dead_letter_queue_name = options[:dead_letter_queue_name]
      policy_options = options.slice(:lazy, :dead_lettering)

      target_queue_options = policy_options.merge(:routing_key => dead_letter_queue_name)
      set_queue_policy!(server, target_queue, target_queue_options)

      dead_letter_queue_options = policy_options.merge(:routing_key => target_queue, :message_ttl => options[:message_ttl])
      set_queue_policy!(server, dead_letter_queue_name, dead_letter_queue_options)
    end

    def set_queue_policy!(server, queue_name, options={})
      logger.info "Setting queue policy: #{server}, #{queue_name}, #{options.inspect}"

      raise ArgumentError.new("server missing")     if server.blank?
      raise ArgumentError.new("queue name missing") if queue_name.blank?

      return unless options[:dead_lettering] || options[:lazy]

      vhost = CGI.escape(config.vhost)
      # no need to worry that the server has the port 5672. Net:HTTP will take care of this. See below.
      request_url = URI("http://#{server}/api/policies/#{vhost}/#{queue_name}_policy")
      request = Net::HTTP::Put.new(request_url)

      # set up queue policy
      definition = {}
      if options[:dead_lettering]
        definition["dead-letter-routing-key"] = options[:routing_key]
        definition["dead-letter-exchange"] = ""
        definition["message-ttl"] = options[:message_ttl] if options[:message_ttl]
      end

      definition["queue-mode"] = "lazy" if options[:lazy]

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

    def run_rabbit_http_request(uri, request, &block)
      request.basic_auth(config.user, config.password)
      request["Content-Type"] = "application/json"
      http = Net::HTTP.new(uri.hostname, config.api_port)
      http.read_timeout = config.dead_lettering_read_timeout
      # don't do this in production:
      # http.set_debug_output(logger.instance_eval{ @logdev.dev })
      http.start do |instance|
        block.call(instance) if block_given?
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
