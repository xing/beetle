require 'pry'
require 'timeout'
require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

class BunnyBehaviorTest < Minitest::Test

  test "publishing fixnums and hashes works in amqp headers" do
    client = Beetle::Client.new
    client.register_queue(:test)
    client.register_message(:test)
    # purge the test queue
    client.purge(:test)
    # empty the dedup store
    client.deduplication_store.flushdb
    # register our handler to the message, check out the message.rb for more stuff you can get from the message object
    message = nil
    client.register_handler(:test) {|msg| message = msg; client.stop_listening }
    # publish our message (NOTE: empty message bodies don't work, most likely due to bugs in bunny/amqp)
    published = client.publish(:test, 'bam', headers: { foo: 1, table: {bar: "baz"}})
    # start listening
    client.listen
    client.stop_publishing
    assert_equal 1, published
    assert_equal "bam", message.data
    headers = message.header.attributes[:headers]
    assert_equal 1, headers["foo"]
    assert_equal({"bar" => "baz"}, headers["table"])
  end


  
  test "publishing redundantly does not leave the garbage in dedup store" do
    Beetle.config.servers = "localhost:5672,localhost:5673"
    client = Beetle::Client.new
    client.register_queue(:test_garbage)
    client.register_message(:test_garbage)
    # purge the test queue
    client.purge(:test_garbage)
    # empty the dedup store
    client.deduplication_store.flushdb

    handler = TestHandler.new(stop_after = 2, client = client)
    client.register_handler(:test_garbage, handler)
    published = client.publish(:test_garbage, 'bam', :redundant =>true)
    listen(client)
    client.stop_publishing

    message = handler.messages_processed.first
    assert_equal 2, published
    assert_equal "bam", message.data
    Beetle::DeduplicationStore::KEY_SUFFIXES.map{|suffix| 
        assert_equal false, client.deduplication_store.exists(message.msg_id, suffix)
    }
  end

  def listen(client , timeout = 1) 
    Timeout.timeout(timeout) do 
      client.listen 
    end
  rescue Timeout::Error 
       puts "Client listen timed out after #{timeout} seconds"
       nil
  end


  class TestHandler < Beetle::Handler

    attr_reader :messages_processed

    def initialize(stop_after, client)
      super()
      @stop_after = stop_after
      @client = client
      @invocations = 0
      @messages_processed = []
    end
    
    def process
      @messages_processed << message
    end

    def post_process
      @invocations += 1
      if @invocations >= @stop_after
          @client.stop_listening
      end
    end

  end


end
