class QrackClientExtTest < Test::Unit::TestCase
  test "should use system-timer for reliable timeouts" do
    Qrack::Client.any_instance.stubs(:create_channel).returns(nil)
    client = Qrack::Client.new 

    Beetle::Timer.expects(:timeout)
    client.send :timeout, 1, 1 do
    end
  end
  
  test "should set send/receive timeouts on the socket" do
    
  end
end