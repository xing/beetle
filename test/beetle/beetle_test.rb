require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class HostnameTest < Test::Unit::TestCase
    test "should use Socket.gethostname if returned name name is fully qualified" do
      Socket.expects(:gethostname).returns("a.b.com")
      assert_equal "a.b.com", Beetle.hostname
    end

    test "should use Socket.gethosbyname if returned name name is not fully qualified" do
      Socket.expects(:gethostname).returns("a")
      Socket.expects(:gethostbyname).with("a").returns(["a.b.com"])
      assert_equal "a.b.com", Beetle.hostname
    end
  end
end
