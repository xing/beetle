require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class RedisConfigurationServerClientInvalidatedMethodTest < Test::Unit::TestCase
    test "should ignore outdated client_invalidated messages" do
      Beetle.config.redis_configuration_client_ids = "rc-client-1,rc-client-2"
      server = RedisConfigurationServer.new

      server.instance_variable_set(:@invalidation_message_token, 2)
      server.client_invalidated("id" => "rc-client-1", "token" => 2)
      old_token = 1.minute.ago.to_f
      server.client_invalidated("id" => "rc-client-2", "token" => 1)

      assert_equal({"rc-client-1" => true}, server.instance_variable_get(:@client_invalidated_messages_received))
    end
  end

  class RedisConfigurationServerInvalidationMessageTokenTest < Test::Unit::TestCase
    test "should initialize the invalidation message token to not reuse old tokens" do
      server = RedisConfigurationServer.new
      sleep 0.1
      server_2 = RedisConfigurationServer.new
      assert server_2.invalidation_message_token > server.invalidation_message_token
    end
  end
  
  class RedisConfigurationServerInvalidationTest < Test::Unit::TestCase
    def setup
      Beetle.config.redis_configuration_client_ids = "rc-client-1,rc-client-2"
      @server = RedisConfigurationServer.new
      @server.stubs(:redis_master).returns(stub('redis stub', :server => 'stubbed_server', :available? => false))
      @server.send(:beetle_client).stubs(:listen).yields
      EM::Timer.stubs(:new).returns(true)
      EventMachine.stubs(:add_periodic_timer).yields
    end
    
    test "should pause watching of the redis server" do 
      EM.stubs(:add_periodic_timer).returns(stub("timer", :cancel => true))
      @server.start
      assert !@server.paused?
      
      @server.send(:redis_unavailable)
      assert @server.paused?
    end
  
    test "should setup an invalidation timeout" do
      EM::Timer.expects(:new)
      @server.send(:redis_unavailable)
    end
    
    test "should continue watching after the invalidation timeout has expired" do
      EM::Timer.expects(:new).yields
      @server.redis_unavailable
      assert !@server.paused?
    end
  end
end
