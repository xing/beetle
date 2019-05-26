require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class SetDeadLetterPolicyTest < Minitest::Test
    def setup
      @server = "localhost:15672"
      @queue_name = "QUEUE_NAME"
      @config = Configuration.new
      @config.logger = Logger.new("/dev/null")
      @dead_lettering = DeadLettering.new(@config)
    end

    test "raises exception when queue name wasn't specified" do
      assert_raises ArgumentError do
        @dead_lettering.set_queue_policy!(@server, "")
      end
    end

    test "raises exception when no server was specified" do
      assert_raises ArgumentError do
        @dead_lettering.set_queue_policy!("", @queue_name)
      end
    end

    test "set_queue_policies! calls set_queue_policy for both target queue and dead letter queue" do
      options = {
        :server => "server", :lazy => true, :dead_lettering => true,
        :queue_name => "QUEUE_NAME", :dead_letter_queue_name => "QUEUE_NAME_dead_letter",
        :message_ttl => 10000
      }
      @dead_lettering.expects(:set_queue_policy!).with("server", "QUEUE_NAME",
                                                       :lazy => true, :dead_lettering => true,
                                                       :routing_key => "QUEUE_NAME_dead_letter")
      @dead_lettering.expects(:set_queue_policy!).with("server", "QUEUE_NAME_dead_letter",
                                                       :lazy => true, :dead_lettering => true,
                                                       :routing_key => "QUEUE_NAME",
                                                       :message_ttl => 10000)
      @dead_lettering.set_queue_policies!(options)
    end

    test "creates a policy by posting to the rabbitmq if dead lettering is enabled" do
      stub_request(:put, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .with(:body => {
               "pattern" => "^QUEUE_NAME$",
               "priority" => 1,
               "apply-to" => "queues",
               "definition" => {
                 "dead-letter-routing-key" => "QUEUE_NAME_dead_letter",
                 "dead-letter-exchange" => ""
               }}.to_json)
        .to_return(:status => 204)

      @dead_lettering.set_queue_policy!(@server, @queue_name, :lazy => false, :dead_lettering => true, :routing_key => "QUEUE_NAME_dead_letter")
    end

    test "creates a policy by posting to the rabbitmq if lazy queues are enabled" do
      stub_request(:put, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .with(:body => {
               "pattern" => "^QUEUE_NAME$",
               "priority" => 1,
               "apply-to" => "queues",
               "definition" => {
                 "queue-mode" => "lazy"
               }}.to_json)
        .to_return(:status => 204)

      @dead_lettering.set_queue_policy!(@server, @queue_name, :lazy => true, :dead_lettering => false)
    end

    test "raises exception when policy couldn't successfully be created" do
      stub_request(:put, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => [405])

      assert_raises DeadLettering::FailedRabbitRequest do
        @dead_lettering.set_queue_policy!(@server, @queue_name, :lazy => true, :dead_lettering => true)
      end
    end

    test "can optionally specify a message ttl" do
      stub_request(:put, "http://localhost:15672/api/policies/%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .with(:body => {
                "pattern" => "^QUEUE_NAME$",
                "priority" => 1,
                "apply-to" => "queues",
                "definition" => {
                  "dead-letter-routing-key" => "QUEUE_NAME_dead_letter",
                  "dead-letter-exchange" => "",
                  "message-ttl" => 10000
                }}.to_json)
        .to_return(:status => 204)

      @dead_lettering.set_queue_policy!(@server, @queue_name, :dead_lettering => true, :message_ttl => 10000, :routing_key => "QUEUE_NAME_dead_letter")
    end

    test "properly encodes the vhost from the configuration" do
      stub_request(:put, "http://localhost:15672/api/policies/foo%2F/QUEUE_NAME_policy")
        .with(basic_auth: ['guest', 'guest'])
        .with(:body => {
               "pattern" => "^QUEUE_NAME$",
               "priority" => 1,
               "apply-to" => "queues",
               "definition" => {
                 "dead-letter-routing-key" => "QUEUE_NAME_dead_letter",
                 "dead-letter-exchange" => ""
               }}.to_json)
        .to_return(:status => 204)

      @config.vhost = "foo/"

      @dead_lettering.set_queue_policy!(@server, @queue_name, :dead_lettering => true, :routing_key => "QUEUE_NAME_dead_letter")
    end

    test "set_queue_policies! calls remove_obsolete_bindings if bindings are part of the options hash" do
      bindings = [{:exchange => "foo", :key => "a.b.c"}]
      options = {
        :server => "server", :lazy => true, :dead_lettering => true,
        :queue_name => "QUEUE_NAME", :dead_letter_queue_name => "QUEUE_NAME_dead_letter",
        :message_ttl => 10000,
        :bindings => bindings
      }
      @dead_lettering.expects(:set_queue_policy!).twice
      @dead_lettering.expects(:remove_obsolete_bindings).with("server", "QUEUE_NAME", bindings)
      @dead_lettering.set_queue_policies!(options)
    end

    test "remove_obsolete_bindings removes an obsolete binding but does not remove the default binding" do
      bindings = [{:exchange => "foo", :key => "QUEUE_NAME"}, {:exchange => "foo", :key => "a.b.c"}]
      stub_request(:get, "http://localhost:15672/api/queues/%2F/QUEUE_NAME/bindings")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 200,
                   :body =>[
                     {
                       "destination_type" => "queue",
                       "source" => "",
                       "routing_key" => "QUEUE_NAME",
                       "destination" => "QUEUE_NAME",
                       "vhost" => "/",
                       "properties_key" => "QUEUE_NAME",
                       "arguments" => {}
                     },
                     {
                       "destination_type" => "queue",
                       "source" => "foo",
                       "routing_key" => "QUEUE_NAME",
                       "destination" => "QUEUE_NAME",
                       "vhost" => "/",
                       "properties_key" => "QUEUE_NAME",
                       "arguments" => {}
                     },
                     {
                       "destination_type" => "queue",
                       "source" => "foo",
                       "routing_key" => "a.b.c",
                       "destination" => "QUEUE_NAME",
                       "vhost" => "/",
                       "properties_key" => "a.b.c",
                       "arguments" => {}
                     },
                     {
                       "destination_type" => "queue",
                       "source" => "foofoo",
                       "routing_key" => "x.y.z",
                       "destination" => "QUEUE_NAME",
                       "vhost" => "/",
                       "properties_key" => "x.y.z",
                       "arguments" => {}
                     }
                   ].to_json)

      stub_request(:delete, "http://localhost:15672/api/bindings/%2F/e/foofoo/q/QUEUE_NAME/x.y.z")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 200)

      @dead_lettering.remove_obsolete_bindings(@server, "QUEUE_NAME", bindings)
    end

    test "raises an error when bindings cannot be retrieved" do
      stub_request(:get, "http://localhost:15672/api/queues/%2F/QUEUE_NAME/bindings")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 500)
      assert_raises(Beetle::DeadLettering::FailedRabbitRequest) { @dead_lettering.remove_obsolete_bindings(@server, "QUEUE_NAME", []) }
    end

    test "raises an error when bindings cannot be deleted" do
      stub_request(:get, "http://localhost:15672/api/queues/%2F/QUEUE_NAME/bindings")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 200, :body => [
                     {
                       "destination_type" => "queue",
                       "source" => "foofoo",
                       "routing_key" => "x.y.z",
                       "destination" => "QUEUE_NAME",
                       "vhost" => "/",
                       "properties_key" => "x.y.z",
                       "arguments" => {}
                     }
                   ].to_json)
      stub_request(:delete, "http://localhost:15672/api/bindings/%2F/e/foofoo/q/QUEUE_NAME/x.y.z")
        .with(basic_auth: ['guest', 'guest'])
        .to_return(:status => 500)

      assert_raises(Beetle::DeadLettering::FailedRabbitRequest) { @dead_lettering.remove_obsolete_bindings(@server, "QUEUE_NAME", []) }
    end

  end
end
