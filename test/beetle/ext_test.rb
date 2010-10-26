require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


class QrackClientExtTest < Test::Unit::TestCase
  def setup
    Qrack::Client.any_instance.stubs(:create_channel).returns(nil)
    @client = Qrack::Client.new
  end


  test "should use system-timer for reliable timeouts" do
    Beetle::Timer.expects(:timeout)
    @client.send :timeout, 1, 1 do
    end
  end

  test "should set send/receive timeouts on the socket" do
    socket_mock = mock("socket")
    @client.instance_variable_set(:@socket, socket_mock)
    @client.stubs(:socket_without_reliable_timeout)

    socket_mock.expects(:setsockopt).with(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, anything)
    socket_mock.expects(:setsockopt).with(Socket::SOL_SOCKET, Socket::SO_SNDTIMEO, anything)
    @client.send(:socket)
  end
end
