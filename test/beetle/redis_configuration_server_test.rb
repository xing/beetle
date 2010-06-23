require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class RedisConfigurationServerClientInvalidatedMethodTest < Test::Unit::TestCase 
    test "should ignore outdated client_invalidated messages" do
      Beetle.config.redis_configuration_client_ids = "rc-client-1,rc-client-2"
      server = RedisConfigurationServer.new([])

      server.instance_variable_set(:@invalidation_message_token, 2)
      server.client_invalidated("id" => "rc-client-1", "token" => 2)
      old_token = 1.minute.ago.to_f
      server.client_invalidated("id" => "rc-client-2", "token" => 1)
      
      assert_equal({"rc-client-1" => true}, server.instance_variable_get(:@client_invalidated_messages_received))
    end
  end
end
