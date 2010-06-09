require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class RedisConfigurationServerClientInvalidatedMethodTest < Test::Unit::TestCase 
    test "should ignore outdated client_invalidated messages" do
      Beetle.config.redis_configuration_client_ids = "rc-client-1,rc-client-2"
      server = RedisConfigurationServer.new
      server.logger.level = Logger::FATAL

      server.instance_variable_set(:@invalidation_message_token, "foo")
      server.client_invalidated("id" => "rc-client-1", "token" => "foo")
      server.client_invalidated("id" => "rc-client-2", "token" => "bar")
      
      assert_equal({"rc-client-1" => true}, server.instance_variable_get(:@client_invalidated_messages_received))
    end
  end
end
