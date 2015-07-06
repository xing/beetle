require 'net/http'
require 'json'

module Beetle
  class DeadLetterQueue
    READ_TIMEOUT = 3 #seconds
    DEFAULT_DEAD_LETTER_MSG_TTL = 1000 #1 second
    RABBIT_API_PORT = 15672

    class FailedRabbitRequest < StandardError; end

    class << self
      def bind_dead_letter_queues!(channel, servers, target_queue, creation_keys = {})
        dead_letter_queue_name = dead_letter_queue_name(target_queue)

        logger.debug("Beetle: creating dead letter queue #{dead_letter_queue_name} with opts: #{creation_keys.inspect}")
        dead_letter_queue = channel.queue(dead_letter_queue_name, creation_keys)

        logger.debug("Beetle: setting #{dead_letter_queue_name} as dead letter queue of #{target_queue} on all servers")
        set_dead_letter_queues!(servers, target_queue)

        logger.debug("Beetle: setting #{target_queue} as dead letter queue of #{dead_letter_queue_name} on all servers")
        set_dead_letter_queues!(servers, dead_letter_queue_name,
           :message_ttl => DeadLetterQueue::DEFAULT_DEAD_LETTER_MSG_TTL,
           :routing_key => target_queue)
      end

      def set_dead_letter_queues!(servers, queue_name, options={})
        servers.each { |server| set_dead_letter_queue!(server, queue_name, options) }
      end

      def set_dead_letter_queue!(server, queue_name, options={})
        raise ArgumentError.new("server missing")     if server.blank?
        raise ArgumentError.new("queue name missing") if queue_name.blank?

        request_url = URI("http://#{server}/api/policies/%2F/#{queue_name}_policy")
        request = Net::HTTP::Put.new(request_url)

        request_body = {
            "pattern" => "^#{queue_name}$",
            "priority" => 1,
            "apply-to" => "queues",
            "definition" => {
              "dead-letter-routing-key" => dead_letter_routing_key(queue_name, options),
              "dead-letter-exchange" => ""
            }
          }

        request_body["definition"].merge!("message-ttl" => options[:message_ttl]) if options[:message_ttl]

        response = run_rabbit_http_request(request_url, request) do |http|
          http.request(request, request_body.to_json)
        end

        if response.code != "204"
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
        request.basic_auth("guest", "guest")
        request["Content-Type"] = "application/json"
        response = Net::HTTP.start(uri.hostname, RABBIT_API_PORT, :read_timeout => READ_TIMEOUT) do |http|
          block.call(http) if block_given?
        end
      end

      def log_error(msg, response)
        logger.error(msg)
        logger.error("Response code was #{response.code}")
        logger.error(response.body)
      end

      def logger
        Beetle.config.logger
      end
    end
  end
end
