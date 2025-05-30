require 'net/http'
require 'json'

module Beetle
  class QueueProperties
    class FailedRabbitRequest < StandardError; end

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def vhost
      CGI.escape(@config.vhost)
    end

    def update_queue_properties!(options, &block)
      logger.info "Updating queue properties: #{options.inspect}"
      options = options.symbolize_keys
      server = options[:server]
      target_queue = options[:queue_name]
      dead_letter_queue_name = options[:dead_letter_queue_name]
      policy_options = options.slice(:lazy, :dead_lettering)

      # The order of policy creation is important.
      # We need to create the policy on the dead letter queue first to have the message_ttl setting
      # in place before the first message comes in. Otherwise a message will not get a ttl
      # applied and stay in the dead letter queue forever (or until manually consumed), thus
      # blocking the head of the queue.
      dead_letter_queue_options = policy_options.merge(:routing_key => target_queue, :message_ttl => options[:message_ttl])
      set_queue_policy!(server, dead_letter_queue_name, dead_letter_queue_options, &block)
      target_queue_options = policy_options.merge(:routing_key => dead_letter_queue_name)
      set_queue_policy!(server, target_queue, target_queue_options, &block)

      remove_obsolete_bindings(server, target_queue, options[:bindings]) if options.has_key?(:bindings)
    end

    def set_queue_policy!(server, queue_name, options={})
      logger.info "Setting queue policy: #{server}, #{queue_name}, #{options.inspect}"

      raise ArgumentError.new("server missing")     if server.blank?
      raise ArgumentError.new("queue name missing") if queue_name.blank?

      return unless options[:dead_lettering] || options[:lazy]

      # no need to worry that the server has the port 5672. Net:HTTP will take care of this. See below.
      policy_name = "#{queue_name}_policy"
      request_path = "/api/policies/#{vhost}/#{policy_name}"

      # set up queue policy
      definition = {}
      if options[:dead_lettering]
        definition["dead-letter-routing-key"] = options[:routing_key]
        definition["dead-letter-exchange"] = ""
        definition["message-ttl"] = options[:message_ttl] if options[:message_ttl]
      end

      definition["queue-mode"] = "lazy" if options[:lazy]

      put_request_body = {
        "pattern" => "^#{queue_name}$",
        "priority" => @config.beetle_policy_priority,
        "apply-to" => "queues",
        "definition" => definition,
      }

      # Allow caller to modify the request body
      if block_given?
        put_request_body = yield(put_request_body, server, queue_name, options)
      end

      is_default_policy = definition == config.broker_default_policy

      get_response = run_api_request(server, Net::HTTP::Get, request_path)

      case get_response.code
      when "200"
        response_body = JSON.parse(get_response.body) rescue {}
        same_policy = put_request_body.all? { |k,v| response_body[k] == v }
        if same_policy
          if is_default_policy
            run_api_request(server, Net::HTTP::Delete, request_path)
          end

          return :ok
        end
      when "404"
        return :ok if is_default_policy
      end

      put_response = run_api_request(server, Net::HTTP::Put, request_path, put_request_body.to_json)

      unless %w(200 201 204).include?(put_response.code)
        log_error("Failed to create policy for queue #{queue_name}", put_response)
        raise FailedRabbitRequest.new("Could not create policy")
      end

      :ok
    end

    def retrieve_queue_properties(server, queue_name)
      response = run_api_request(server, Net::HTTP::Get, "/api/queues/#{vhost}/#{queue_name}")
      code = response.code.to_i

      return nil if [404, 410].include?(code)

      if code >= 400
        log_error("Failed to retrieve queue properties for #{queue_name}", response)
        raise FailedRabbitRequest.new("Could not retrieve queue properties")
      end

      JSON.parse(response.body)
    end

    def remove_obsolete_bindings(server, queue_name, bindings)
      logger.debug "Removing obsolete bindings"
      raise ArgumentError.new("server missing")     if server.blank?
      raise ArgumentError.new("queue name missing") if queue_name.blank?
      raise ArgumentError.new("bindings missing")   if bindings.nil?

      desired_bindings = bindings.each_with_object({}) do |b, desired|
        desired[[b[:exchange], b[:key]]] = b.except(:exchange, :key)
      end

      server_bindings = retrieve_bindings(server, queue_name)
      server_bindings.each do |b|
        next unless b["destination_type"] == "queue" || b["destination"] == queue_name
        next if b["source"] == ""
        source_route = b.values_at("source", "routing_key")
        unless desired_bindings.has_key?(source_route)
          logger.info "Removing obsolete binding: #{b.inspect}"
          remove_binding(server, queue_name, b["source"], b["properties_key"])
        end
      end
    end

    def retrieve_bindings(server, queue_name)
      response = run_api_request(server, Net::HTTP::Get, "/api/queues/#{vhost}/#{queue_name}/bindings")

      unless response.code == "200"
        log_error("Failed to retrieve bindings for queue #{queue_name}", response)
        raise FailedRabbitRequest.new("Could not retrieve queue bindings")
      end

      JSON.parse(response.body)
    end

    def remove_binding(server, queue_name, exchange, properties_key)
      response = run_api_request(server, Net::HTTP::Delete, "/api/bindings/#{vhost}/e/#{exchange}/q/#{queue_name}/#{properties_key}")

      unless %w(200 201 204).include?(response.code)
        log_error("Failed to remove obsolete binding for queue #{queue_name}", response)
        raise FailedRabbitRequest.new("Could not retrieve queue bindings")
      end
    end

    def run_api_request(server, request_const, path, *request_args)
      connection_options = config.connection_options_for_server(server)

      derived_api_port = "1#{connection_options[:port]}".to_i
      request_url = URI("http://#{connection_options[:host]}:#{derived_api_port}#{path}")

      request = request_const.new(request_url).tap do |req|
        req.basic_auth(connection_options[:user], connection_options[:pass])
        case request_const::METHOD
        when 'GET'
          req["Accept"] = "application/json"
        when 'PUT'
          req["Content-Type"] = "application/json"
        end
      end

      http = Net::HTTP.new(connection_options[:host], derived_api_port)
      http.use_ssl = connection_options[:ssl]
      http.read_timeout = config.rabbitmq_api_read_timeout
      http.write_timeout = config.rabbitmq_api_write_timeout if http.respond_to?(:write_timeout=)

      http.start do |instance|
        instance.request(request, *request_args)
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
