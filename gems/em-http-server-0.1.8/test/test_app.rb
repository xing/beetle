require 'test/unit'
require 'em-http-server'

require 'eventmachine'


#--------------------------------------

module EventMachine
  class HttpHandler < EM::HttpServer::Server
    def process_http_request
      send_data generate_response()
      close_connection_after_writing
    end
  end
end

#--------------------------------------

require 'socket'

class TestApp < Test::Unit::TestCase

  TestHost = "127.0.0.1"
  TestPort = 8911

  TestResponse_1 = <<EORESP
HTTP/1.0 200 ...
Content-length: 4
Content-type: text/plain
Connection: close

1234
EORESP

  Thread.abort_on_exception = true

  def test_simple_get
    received_response = nil

    EventMachine::HttpHandler.class_eval do
      def generate_response
        TestResponse_1
      end
    end


    EventMachine.run do
      EventMachine.start_server TestHost, TestPort, EventMachine::HttpHandler
      EventMachine.add_timer(1) {raise "timed out"} # make sure the test completes

      cb = proc do
        tcp = TCPSocket.new TestHost, TestPort
        tcp.write "GET / HTTP/1.0\r\n\r\n"
        received_response = tcp.read
      end
      eb = proc { EventMachine.stop }
      EventMachine.defer cb, eb
    end

    assert_equal( TestResponse_1, received_response )
  end




  # This frowsy-looking protocol handler allows the test harness to make some
  # its local variables visible, so we can set them here and they can be asserted later.
  class MyTestServer < EventMachine::HttpHandler

    def initialize *args
      super
    end
    def generate_response
      @assertions.call
      TestResponse_1
    end
  end



  def test_parameters
    path_info = "/test.html"
    query_string = "a=b&c=d"
    cookie = "eat_me=I'm a cookie"
    etag = "12345"

    # collect all the stuff we want to assert outside the actual test,
    # to ensure it gets asserted even if the test catches some exception.
    received_response = nil
    request_http = {}
    request_uri = ""
    request_query = ""
    request_method = ""


    EventMachine.run do
      EventMachine.start_server(TestHost, TestPort, MyTestServer) do |conn|
        # In each accepted connection, set up a procedure that will copy
        # the request parameters into a local variable visible here, so
        # we can assert the values later.
        conn.instance_eval do
          @assertions = proc {
            request_method = @http_request_method
            request_uri = @http_request_uri
            request_query = @http_query_string
            request_http = @http
          }
        end
      end
      EventMachine.add_timer(1) {raise "timed out"} # make sure the test completes

      cb = proc do
        tcp = TCPSocket.new TestHost, TestPort
        data = [
          "GET #{path_info}?#{query_string} HTTP/1.1\r\n",
          "Cookie: #{cookie}\r\n",
          "If-none-match: #{etag}\r\n",
          "\r\n"
        ].join
        tcp.write(data)
        received_response = tcp.read
      end
      eb = proc { EventMachine.stop }
      EventMachine.defer cb, eb
    end

    assert_equal( TestResponse_1, received_response )
    assert_equal( path_info, request_uri )
    assert_equal( query_string, request_query )
    assert_equal( cookie, request_http[:cookie] )
    assert_equal( etag, request_http[:if_none_match] )
    assert_equal( nil, request_http[:content_type] )
    assert_equal( "GET", request_method )
  end


  def test_headers
    received_header_string = nil
    received_header_ary = nil

    EventMachine.run do
      EventMachine.start_server(TestHost, TestPort, MyTestServer) do |conn|
        # In each accepted connection, set up a procedure that will copy
        # the request parameters into a local variable visible here, so
        # we can assert the values later.
        # The @http_headers is set automatically and can easily be parsed.
        # It isn't automatically parsed into Ruby values because that is
        # a costly operation, but we should provide an optional method that
        # does the parsing so it doesn't need to be done by users.
        conn.instance_eval do
          @assertions = proc do
            received_header_string = @http_headers
            received_header_ary = @http.map {|line| line }
          end
        end
      end

      cb = proc do
        tcp = TCPSocket.new TestHost, TestPort
        data = [
          "GET / HTTP/1.1\r\n",
          "aaa: 111\r\n",
          "bbb: 222\r\n",
          "ccc: 333\r\n",
          "ddd: 444\r\n",
          "\r\n"
        ].join
        tcp.write data
        received_response = tcp.read
      end
      eb = proc { EventMachine.stop }
      EventMachine.defer cb, eb

      EventMachine.add_timer(1) {raise "timed out"} # make sure the test completes
    end

    assert_equal( ["GET / HTTP/1.1", "aaa: 111", "bbb: 222", "ccc: 333", "ddd: 444"], received_header_string )
    assert_equal( [[:aaa,"111"], [:bbb,"222"], [:ccc,"333"], [:ddd,"444"]], received_header_ary )
  end





  def test_post
    received_header_string = nil
    post_content = "1234567890"
    content_type = "text/plain"
    received_post_content = ""
    received_content_type = ""

    EventMachine.run do
      EventMachine.start_server(TestHost, TestPort, MyTestServer) do |conn|
        # In each accepted connection, set up a procedure that will copy
        # the request parameters into a local variable visible here, so
        # we can assert the values later.
        # The @http_post_content variable is set automatically.
        conn.instance_eval do
          @assertions = proc do
            received_post_content = @http_content
            received_content_type = @http[:content_type]
          end
        end
      end
      EventMachine.add_timer(1) {raise "timed out"} # make sure the test completes

      cb = proc do
        tcp = TCPSocket.new TestHost, TestPort
        data = [
          "POST / HTTP/1.1\r\n",
          "Content-type: #{content_type}\r\n",
          "Content-length: #{post_content.length}\r\n",
          "\r\n",
          post_content
        ].join
        tcp.write(data)
        received_response = tcp.read
      end
      eb = proc do
        EventMachine.stop
      end
      EventMachine.defer cb, eb
    end

    assert_equal( post_content, received_post_content)
    assert_equal( content_type, received_content_type)
  end


  def test_invalid
    received_response = nil

    EventMachine.run do
      EventMachine.start_server(TestHost, TestPort, MyTestServer) do |conn|
        conn.instance_eval do
          @assertions = proc do
          end
        end
      end

      cb = proc do
        tcp = TCPSocket.new TestHost, TestPort
        data = [
          "GET HTTP/1.1\r\n",
          "\r\n"
        ].join
        tcp.write data
        received_response = tcp.read
      end
      eb = proc { EventMachine.stop }
      EventMachine.defer cb, eb

      EventMachine.add_timer(1) {raise "timed out"} # make sure the test completes
    end

    assert_equal( "HTTP/1.1 400 Bad request\r\nConnection: close\r\nContent-type: text/plain\r\n\r\nDetected error: HTTP code 400", received_response )
  end

  def test_invalid_custom
    received_response = nil

    MyTestServer.class_eval do
      def http_error_string(code, desc)
        return 'custom'
      end
    end

    EventMachine.run do
      EventMachine.start_server(TestHost, TestPort, MyTestServer) do |conn|
        conn.instance_eval do
          @assertions = proc do
          end
        end
      end

      cb = proc do
        tcp = TCPSocket.new TestHost, TestPort
        data = [
          "GET HTTP/1.1\r\n",
          "\r\n"
        ].join
        tcp.write data
        received_response = tcp.read
      end
      eb = proc { EventMachine.stop }
      EventMachine.defer cb, eb

      EventMachine.add_timer(1) {raise "timed out"} # make sure the test completes
    end

    assert_equal( "custom", received_response )
  end


end