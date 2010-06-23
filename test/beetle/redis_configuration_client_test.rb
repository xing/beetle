require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class RedisConfigurationClientOutdatedMessagesTest < Test::Unit::TestCase 
    test "should ignore outdated invalidate messages" do
      new_payload = {"token" => 2}
      old_payload = {"token" => 1}
      client = RedisConfigurationClient.new
      
      client.expects(:invalidate!).once
      
      client.invalidate(new_payload)
      client.invalidate(old_payload)
    end
  end
end
