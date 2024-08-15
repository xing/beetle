require File.expand_path('../websocket_native_ext', __FILE__)

# WebSocket Native Extension
# @author Bernard "Imanel" Potocki
# @see http://github.com/imanel/websocket-ruby-extension main repository
module WebSocket

  if RUBY_PLATFORM =~ /java/
    require 'jruby'
    org.imanel.websocket.WebSocketNativeExtService.new.basicLoad(JRuby.runtime)
  end

  module Frame
    class Data < String
      def mask_native(payload, mask)
        ::WebSocket::Native::Data.mask(payload, mask)
      end
    end
  end

  module Native
    class Data
      def self.mask(payload, mask)
        @instance ||= new
        @instance.mask(payload, mask)
      end
    end
  end

end
