require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class HostnameTest < Minitest::Test
   test "should use canonical name if possible " do
      addr = mock("addr")
      addr.expects(:canonname).returns("a.b.com")
      Socket.expects(:gethostname).returns("a.b.com")
      Addrinfo.expects(:getaddrinfo).with("a", nil, nil, :STREAM, nil, Socket::AI_CANONNAME).returns([addr])
      assert_equal "a.b.com", Beetle.hostname
    end

    test "should use Socket.gethostbyname if Addrinfo raises" do
      Socket.expects(:gethostname).returns("a")
      Addrinfo.expects(:getaddrinfo).with("a", nil, nil, :STREAM, nil, Socket::AI_CANONNAME).raises("murks")
      assert_equal "a", Beetle.hostname
    end
  end
end
