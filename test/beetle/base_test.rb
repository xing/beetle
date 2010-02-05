require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Beetle
  class BaseTest < Test::Unit::TestCase
    test "initially we should have no exchanges" do
      @bs = Base.new(Client.new)
      assert_equal({}, @bs.instance_variable_get("@exchanges"))
    end
  end

  class HandlerRegistrationTest < Test::Unit::TestCase
    def setup
      @bs = Base.new(Client.new)
    end

    test "registering a queue should store it in the configuration with symbolized option keys" do
      opts = {"durable" => true}
      @bs.send(:register_queue, "some_queue", opts)
      assert_equal({:durable => true}, @bs.amqp_config["queues"]["some_queue"])
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
