require 'test/unit'
require 'em-http-server'

require 'eventmachine'

#--------------------------------------


class TestDelegatedHttpResponse < Test::Unit::TestCase

	# This is a delegate class that (trivially) implements the
	# several classes needed to work with HttpResponse.
	#
	class D
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

	def setup
	end


	def teardown
	end


	def test_properties
		a = EM::DelegatedHttpResponse.new( D.new )
		a.status = 200
		a.content = "Some content"
		a.headers["Content-type"] = "text/xml"
	end

	def test_header_sugarings
		a = EM::DelegatedHttpResponse.new( D.new )
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
		d = D.new
		a = EM::DelegatedHttpResponse.new( d )
		a.status = 200
		a.send_response
		assert_equal([
			     "HTTP/1.1 200 ...\r\n",
			     "Content-length: 0\r\n",
			     "\r\n"
		].join, d.output_data)
		assert_equal( true, d.closed_after_writing )
	end

	def test_send_response_1
		d = D.new
		a = EM::DelegatedHttpResponse.new( d )
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
		].join, d.output_data)
		assert( d.closed_after_writing )
	end

	def test_send_response_no_close
		d = D.new
		a = EM::DelegatedHttpResponse.new( d )
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
		].join, d.output_data)
		assert( ! d.closed_after_writing )
	end

	def test_send_response_multiple_times
		a = EM::DelegatedHttpResponse.new( D.new )
		a.status = 200
		a.send_response
		assert_raise( RuntimeError ) {
			a.send_response
		}
	end

	def test_send_headers
		d = D.new
		a = EM::DelegatedHttpResponse.new( d )
		a.status = 200
		a.send_headers
		assert_equal([
			     "HTTP/1.1 200 ...\r\n",
			     "Content-length: 0\r\n",
			     "\r\n"
		].join, d.output_data)
		assert( ! d.closed_after_writing )
		assert_raise( RuntimeError ) {
			a.send_headers
		}
	end

	def test_send_chunks
		d = D.new
		a = EM::DelegatedHttpResponse.new( d )
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
		].join, d.output_data)
		assert( !d.closed_after_writing )
	end

	def test_send_chunks_with_close
		d = D.new
		a = EM::DelegatedHttpResponse.new( d )
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
		].join, d.output_data)
		assert( d.closed_after_writing )
	end

end



