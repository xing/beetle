require 'evma_httpserver'

module Beetle
  class RedisConfigurationHttpServer < EM::Connection
     include EM::HttpServer

     def post_init
       super
       no_environment_strings
     end

    cattr_accessor :config_server

    def process_http_request
      # the http request details are available via the following instance variables:
      #   @http_protocol
      #   @http_request_method
      #   @http_cookie
      #   @http_if_none_match
      #   @http_content_type
      #   @http_path_info
      #   @http_request_uri
      #   @http_query_string
      #   @http_post_content
      #   @http_headers
      response = EM::DelegatedHttpResponse.new(self)
      response.status = 200
      response.content_type 'text/plain'

      case @http_request_uri
      when '/'
        server_status(response)
      else
        not_found(response)
      end
      response.send_response
    end

    def server_status(response)
      config_server.redis.refresh
      response.content = <<"EOF"
Current redis master: #{config_server.current_master.server}
Available redis slaves: #{config_server.available_slaves.map(&:server).join(', ')}
Configured rcs clients: #{config_server.client_ids.to_a.join(', ')}
EOF
    end

    def not_found(response)
      response.status = 404
    end
  end
end
