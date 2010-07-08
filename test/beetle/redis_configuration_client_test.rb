require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class RedisConfigurationClientTest < Test::Unit::TestCase 
    test "should ignore outdated invalidate messages" do
      new_payload = {"token" => 2}
      old_payload = {"token" => 1}
      client = RedisConfigurationClient.new
      
      client.expects(:invalidate!).once
      
      client.invalidate(new_payload)
      client.invalidate(old_payload)
    end

    test "should ignore outdated reconfigure messages" do
      new_payload = {"token" => 2, "server" => "master:2"}
      old_payload = {"token" => 1, "server" => "master:1"}
      client = RedisConfigurationClient.new
      client.stubs(:read_redis_master_file).returns("")

      client.expects(:write_redis_master_file).once
      
      client.reconfigure(new_payload)
      client.reconfigure(old_payload)
    end
  end
end
