require 'test/unit'
require 'em-http-server'

require 'eventmachine'

#--------------------------------------

module EventMachine

  # This is a test harness wired into the HttpResponse class so we
  # can test it without requiring any actual network communication.
  #
  class HttpResponse
    attr_reader :output_data
    attr_reader :closed_after_writing

    def send_data data
      @output_data ||= ""
      @output_data << data
    end
    def close_connection_after_writing
      @closed_after_writing = true
    end
  end
end

#--------------------------------------


class TestHttpResponse < Test::Unit::TestCase

  def test_properties
    a = EventMachine::HttpResponse.new
    a.status = 200
    a.content = "Some content"
    a.headers["Content-type"] = "text/xml"
  end

  def test_header_sugarings
    a = EventMachine::HttpResponse.new
    a.content_type "text/xml"
    a.set_cookie "a=b"
    a.headers["X-bayshore"] = "aaaa"

    assert_equal({
      "Content-type" => "text/xml",
      "Set-cookie" => ["a=b"],
      "X-bayshore" => "aaaa"
    }, a.headers)
  end

  def test_send_response
    a = EventMachine::HttpResponse.new
    a.status = 200
    a.send_response
    assert_equal([
           "HTTP/1.1 200 ...\r\n",
           "Content-length: 0\r\n",
           "\r\n"
    ].join, a.output_data)
    assert_equal( true, a.closed_after_writing )
  end

  def test_send_response_with_status
    a = EventMachine::HttpResponse.new
    a.status = 200
    a.status_string = "OK-TEST"
    a.send_response
    assert_equal([
           "HTTP/1.1 200 OK-TEST\r\n",
           "Content-length: 0\r\n",
           "\r\n"
    ].join, a.output_data)
    assert_equal( true, a.closed_after_writing )
  end

  def test_send_response_1
    a = EventMachine::HttpResponse.new
    a.status = 200
    a.content_type "text/plain"
    a.content = "ABC"
    a.send_response
    assert_equal([
           "HTTP/1.1 200 ...\r\n",
           "Content-length: 3\r\n",
           "Content-type: text/plain\r\n",
           "\r\n",
           "ABC"
    ].join, a.output_data)
    assert( a.closed_after_writing )
  end

  def test_send_response_no_close
    a = EventMachine::HttpResponse.new
    a.status = 200
    a.content_type "text/plain"
    a.content = "ABC"
    a.keep_connection_open
    a.send_response
    assert_equal([
           "HTTP/1.1 200 ...\r\n",
           "Content-length: 3\r\n",
           "Content-type: text/plain\r\n",
           "\r\n",
           "ABC"
    ].join, a.output_data)
    assert( ! a.closed_after_writing )
  end

  def test_send_response_no_close_with_a_404_response
    a = EventMachine::HttpResponse.new
    a.status = 404
    a.content_type "text/plain"
    a.content = "ABC"
    a.keep_connection_open
    a.send_response
    assert_equal([
           "HTTP/1.1 404 ...\r\n",
           "Content-length: 3\r\n",
           "Content-type: text/plain\r\n",
           "\r\n",
           "ABC"
    ].join, a.output_data)
    assert( ! a.closed_after_writing )
  end

  def test_send_response_no_close_with_a_201_response
    a = EventMachine::HttpResponse.new
    a.status = 201
    a.content_type "text/plain"
    a.content = "ABC"
    a.keep_connection_open
    a.send_response
    assert_equal([
           "HTTP/1.1 201 ...\r\n",
           "Content-length: 3\r\n",
           "Content-type: text/plain\r\n",
           "\r\n",
           "ABC"
    ].join, a.output_data)
    assert( ! a.closed_after_writing )
  end

  def test_send_response_no_close_with_a_500_response
    a = EventMachine::HttpResponse.new
    a.status = 500
    a.content_type "text/plain"
    a.content = "ABC"
    a.keep_connection_open
    a.send_response
    assert_equal([
           "HTTP/1.1 500 ...\r\n",
           "Content-length: 3\r\n",
           "Content-type: text/plain\r\n",
           "\r\n",
           "ABC"
    ].join, a.output_data)
    assert( a.closed_after_writing )
  end

  def test_send_response_multiple_times
    a = EventMachine::HttpResponse.new
    a.status = 200
    a.send_response
    assert_raise( RuntimeError ) {
      a.send_response
    }
  end

  def test_send_headers
    a = EventMachine::HttpResponse.new
    a.status = 200
    a.send_headers
    assert_equal([
           "HTTP/1.1 200 ...\r\n",
           "Content-length: 0\r\n",
           "\r\n"
    ].join, a.output_data)
    assert( ! a.closed_after_writing )
    assert_raise( RuntimeError ) {
      a.send_headers
    }
  end

  def test_send_chunks
    a = EventMachine::HttpResponse.new
    a.chunk "ABC"
    a.chunk "DEF"
    a.chunk "GHI"
    a.keep_connection_open
    a.send_response
    assert_equal([
           "HTTP/1.1 200 ...\r\n",
           "Transfer-encoding: chunked\r\n",
           "\r\n",
           "3\r\n",
           "ABC\r\n",
           "3\r\n",
           "DEF\r\n",
           "3\r\n",
           "GHI\r\n",
           "0\r\n",
           "\r\n"
    ].join, a.output_data)
    assert( !a.closed_after_writing )
  end

  def test_send_chunks_with_close
    a = EventMachine::HttpResponse.new
    a.chunk "ABC"
    a.chunk "DEF"
    a.chunk "GHI"
    a.send_response
    assert_equal([
           "HTTP/1.1 200 ...\r\n",
           "Transfer-encoding: chunked\r\n",
           "\r\n",
           "3\r\n",
           "ABC\r\n",
           "3\r\n",
           "DEF\r\n",
           "3\r\n",
           "GHI\r\n",
           "0\r\n",
           "\r\n"
    ].join, a.output_data)
    assert( a.closed_after_writing )
  end

end



