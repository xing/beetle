# Em::Http::Server

Simple http server to be used with Eventmachine.

## Installation

Add this line to your application's Gemfile:

    gem 'em-http-server'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install em-http-server

## Usage

    require 'eventmachine'
    require 'em-http-server'

    class HTTPHandler < EM::HttpServer::Server

        def process_http_request
              puts  @http_request_method
              puts  @http_request_uri
              puts  @http_query_string
              puts  @http_protocol
              puts  @http_content
              puts  @http[:cookie]
              puts  @http[:content_type]
              # you have all the http headers in this hash
              puts  @http.inspect

              response = EM::DelegatedHttpResponse.new(self)
              response.status = 200
              response.content_type 'text/html'
              response.content = 'It works'
              response.send_response
        end

        def http_request_errback e
          # printing the whole exception
          puts e.inspect
        end

    end

    EM::run do
        EM::start_server("0.0.0.0", 80, HTTPHandler)
    end

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
