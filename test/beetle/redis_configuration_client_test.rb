require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class RedisConfigurationClientTest < Test::Unit::TestCase
    def setup
      Beetle.config.redis_server_list = ["redis:0", "redis:1"]
      @client = RedisConfigurationClient.new
      @client.stubs(:beetle).returns(stub(:listen => nil, :config => Beetle.config))
      @client.stubs(:touch_master_file)
    end

    test "should exit when started with less than two redis configured" do
      Beetle.config.redis_server_list = []
      assert_raise Beetle::ConfigurationError do
        @client.start
      end
    end

    test "should ignore outdated invalidate messages" do
      new_payload = {"token" => 2}
      old_payload = {"token" => 1}

      @client.expects(:invalidate!).once

      @client.invalidate(new_payload)
      @client.invalidate(old_payload)
    end

    test "should ignore outdated reconfigure messages" do
      new_payload = {"token" => 2, "server" => "master:2"}
      old_payload = {"token" => 1, "server" => "master:1"}
      @client.stubs(:read_redis_master_file).returns("")

      @client.expects(:write_redis_master_file).once

      @client.reconfigure(new_payload)
      @client.reconfigure(old_payload)
    end

    test "should clear redis master file if redis from master file is slave" do
      @client.stubs(:redis_master_from_master_file).returns(stub(:master? => false))
      @client.expects(:clear_redis_master_file)
      @client.start
    end

    test "should clear redis master file if redis from master file is not available" do
      @client.stubs(:redis_master_from_master_file).returns(nil)
      @client.expects(:clear_redis_master_file)
      @client.start
    end
  end
end
