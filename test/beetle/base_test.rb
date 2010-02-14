require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Beetle
  class BaseTest < Test::Unit::TestCase
    test "initially we should have no exchanges" do
      @bs = Base.new(Client.new)
      assert_equal({}, @bs.instance_variable_get("@exchanges"))
    end

    test "initially we should have no queues" do
      @bs = Base.new(Client.new)
      assert_equal({}, @bs.instance_variable_get("@queues"))
    end

    test "the error method should raise a beetle error" do
      @bs = Base.new(Client.new)
      assert_raises(Error){ @bs.send(:error, "ha") }
    end
  end

  class BaseServerManagementTest < Test::Unit::TestCase
    def setup
      @client = Client.new
      @bs = Base.new(@client)
    end

    test "server should be initialized" do
      assert_equal @bs.servers.first, @bs.server
    end

    test "current_host should return the hostname of the current server" do
      @bs.server = "localhost:123"
      assert_equal "localhost", @bs.send(:current_host)
    end

    test "current_port should return the port of the current server as an integer" do
      @bs.server = "localhost:123"
      assert_equal 123, @bs.send(:current_port)
    end

    test "current_port should return the default rabbit port if server string does not contain a port" do
      @bs.server = "localhost"
      assert_equal 5672, @bs.send(:current_port)
    end

    test "set_current_server shoud set the current server" do
      @bs.send(:set_current_server, "xxx:123")
      assert_equal "xxx:123", @bs.server
    end
  end
end
