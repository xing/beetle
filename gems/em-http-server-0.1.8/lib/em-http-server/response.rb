# EventMachine HTTP Server
# HTTP Response-support class
#
# Author:: blackhedd (gmail address: garbagecat10).
# 
# Copyright (C) 2006-07 by Francis Cianfrocca. All Rights Reserved.
#
# This program is made available under the terms of the GPL version 2.
#
#----------------------------------------------------------------------------
#
# Copyright (C) 2006 by Francis Cianfrocca. All Rights Reserved.
#
# Gmail: garbagecat10
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
#
#---------------------------------------------------------------------------
#

module EventMachine

	# This class provides a wide variety of features for generating and
	# dispatching HTTP responses. It allows you to conveniently generate
	# headers and content (including chunks and multiparts), and dispatch
	# responses (including deferred or partially-complete responses).
	#
	# Although HttpResponse is coded as a class, it's not complete as it
	# stands. It assumes that it has certain of the behaviors of
	# EventMachine::Connection. You must add these behaviors, either by
	# subclassing HttpResponse, or using the alternate version of this
	# class, DelegatedHttpResponse. See the test cases for current information
	# on which behaviors you have to add.
	#
	# TODO, someday it would be nice to provide a version of this functionality
	# that is coded as a Module, so it can simply be mixed into an instance of
	# EventMachine::Connection.
	#
	class HttpResponse
		attr_accessor :status, :status_string, :content, :headers, :chunks, :multiparts

		def initialize
			@headers = {}
      @keep_connection_open = false
		end

		def keep_connection_open arg=true
			@keep_connection_open = arg
		end

		# sugarings for headers
		def content_type *mime
			if mime.length > 0
				@headers["Content-type"] = mime.first.to_s
			else
				@headers["Content-type"]
			end
		end

		# Sugaring for Set-cookie headers. These are a pain because there can easily and
		# legitimately be more than one. So we use an ugly verb to signify that.
		# #add_set_cookies does NOT disturb the set-cookie headers which may have been
		# added on a prior call. #set_cookie clears them out first.
		def add_set_cookie *ck
			if ck.length > 0
				h = (@headers["Set-cookie"] ||= [])
				ck.each {|c| h << c}
			end
		end
		def set_cookie *ck
			h = (@headers["Set-cookie"] ||= [])
			if ck.length > 0
				h.clear
				add_set_cookie *ck
			else
				h
			end
		end


		# This is intended to send a complete HTTP response, including closing the connection
		# if appropriate at the end of the transmission. Don't use this method to send partial
		# or iterated responses. This method will send chunks and multiparts provided they
		# are all available when we get here.
		# Note that the default @status is 200 if the value doesn't exist.
		def send_response
			send_headers
			send_body
			send_trailer
			close_connection_after_writing unless (@keep_connection_open and (@status || 200) < 500)
		end

		# Send the headers out in alpha-sorted order. This will degrade performance to some
		# degree, and is intended only to simplify the construction of unit tests.
		#
		def send_headers
			raise "sent headers already" if @sent_headers
			@sent_headers = true

			fixup_headers

			ary = []
			ary << "HTTP/1.1 #{@status || 200} #{@status_string || '...'}\r\n"
			ary += generate_header_lines(@headers)
			ary << "\r\n"

			send_data ary.join
		end


		def generate_header_lines in_hash
			out_ary = []
			in_hash.keys.sort.each {|k|
				v = in_hash[k]
				if v.is_a?(Array)
					v.each {|v1| out_ary << "#{k}: #{v1}\r\n" }
				else
					out_ary << "#{k}: #{v}\r\n"
				end
			}
			out_ary
		end
		private :generate_header_lines


		# Examine the content type and data and other things, and perform a final
		# fixup of the header array. We expect this to be called just before sending
		# headers to the remote peer.
		# In the case of multiparts, we ASSUME we will get called before any content
		# gets sent out, because the multipart boundary is created here.
		#
		def fixup_headers
			if @content
				@headers["Content-length"] = content.to_s.bytesize
			elsif @chunks
				@headers["Transfer-encoding"] = "chunked"
				# Might be nice to ENSURE there is no content-length header,
				# but how to detect all the possible permutations of upper/lower case?
			elsif @multiparts
				@multipart_boundary = self.class.concoct_multipart_boundary
				@headers["Content-type"] = "multipart/x-mixed-replace; boundary=\"#{@multipart_boundary}\""
			else
				@headers["Content-length"] = 0
			end
		end

		# we send either content, chunks, or multiparts. Content can only be sent once.
		# Chunks and multiparts can be sent any number of times.
		# DO NOT close the connection or send any goodbye kisses. This method can
		# be called multiple times to send out chunks or multiparts.
		def send_body
			if @content
				send_content
			elsif @chunks
				send_chunks
			elsif @multiparts
				send_multiparts
			else
				@content = ""
				send_content
			end
		end

		# send a trailer which depends on the type of body we're dealing with.
		# The assumption is that we're about to end the transmission of this particular
		# HTTP response. (A connection-close may or may not follow.)
		#
		def send_trailer
			send_headers unless @sent_headers
			if @content
				# no-op
			elsif @chunks
				unless @last_chunk_sent
					chunk ""
					send_chunks
				end
			elsif @multiparts
				# in the lingo of RFC 2046/5.1.1, we're sending an "epilog"
				# consisting of a blank line. I really don't know how that is
				# supposed to interact with the case where we leave the connection
				# open after transmitting the multipart response.
				send_data "\r\n--#{@multipart_boundary}--\r\n\r\n"
			else
				# no-op
			end
		end

		def send_content
			raise "sent content already" if @sent_content
			@sent_content = true
			send_data((@content || "").to_s)
		end

		# add a chunk to go to the output.
		# Will cause the headers to pick up "content-transfer-encoding"
		# Add the chunk to a list. Calling #send_chunks will send out the
		# available chunks and clear the chunk list WITHOUT closing the connection,
		# so it can be called any number of times.
		# TODO!!! Per RFC2616, we may not send chunks to an HTTP/1.0 client.
		# Raise an exception here if our user tries to do so.
		# Chunked transfer coding is defined in RFC2616 pgh 3.6.1.
		# The argument can be a string or a hash. The latter allows for
		# sending chunks with extensions (someday).
		#
		def chunk text
			@chunks ||= []
			@chunks << text
		end

		# send the contents of the chunk list and clear it out.
		# ASSUMES that headers have been sent.
		# Does NOT close the connection.
		# Can be called multiple times.
		# According to RFC2616, phg 3.6.1, the last chunk will be zero length.
		# But some caller could accidentally set a zero-length chunk in the middle
		# of the stream. If that should happen, raise an exception.
		# The reason for supporting chunks that are hashes instead of just strings
		# is to enable someday supporting chunk-extension codes (cf the RFC).
		# TODO!!! We're not supporting the final entity-header that may be
		# transmitted after the last (zero-length) chunk.
		#
		def send_chunks
			send_headers unless @sent_headers
			while chunk = @chunks.shift
				raise "last chunk already sent" if @last_chunk_sent
				text = chunk.is_a?(Hash) ? chunk[:text] : chunk.to_s
				send_data "#{format("%x", text.length).upcase}\r\n#{text}\r\n"
				@last_chunk_sent = true if text.length == 0
			end
		end

		# To add a multipart to the outgoing response, specify the headers and the
		# body. If only a string is given, it's treated as the body (in this case,
		# the header is assumed to be empty).
		#
		def multipart arg
			vals = if arg.is_a?(String)
				{:body => arg, :headers => {}}
			else
				arg
			end

			@multiparts ||= []
			@multiparts << vals
		end

		# Multipart syntax is defined in RFC 2046, pgh 5.1.1 et seq.
		# The CRLF which introduces the boundary line of each part (content entity)
		# is defined as being part of the boundary, not of the preceding part.
		# So we don't need to mess with interpreting the last bytes of a part
		# to ensure they are CRLF-terminated.
		#
		def send_multiparts
			send_headers unless @sent_headers
			while part = @multiparts.shift
				send_data "\r\n--#{@multipart_boundary}\r\n"
				send_data( generate_header_lines( part[:headers] || {} ).join)
				send_data "\r\n"
				send_data part[:body].to_s
			end
		end

		# TODO, this is going to be way too slow. Cache up the uuidgens.
		#
		def self.concoct_multipart_boundary
			@multipart_index ||= 0
			@multipart_index += 1
			if @multipart_index >= 1000
				@multipart_index = 0
				@multipart_guid = nil
			end
			@multipart_guid ||= `uuidgen -r`.chomp.gsub(/\-/,"")
			"#{@multipart_guid}#{@multipart_index}"
		end
		
		def send_redirect location
			@status = 302 # TODO, make 301 available by parameter
      @status_string = "Moved Temporarily"
			@headers["Location"] = location
			send_response
		end
	end
end

#----------------------------------------------------------------------------

require 'forwardable'

module EventMachine
	class DelegatedHttpResponse < HttpResponse
		extend Forwardable
		def_delegators :@delegate,
			:send_data,
			:close_connection,
			:close_connection_after_writing

		def initialize dele
			super()
			@delegate = dele
		end
	end
end

