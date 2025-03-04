require 'pry'
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
    publisher = Beetle::Client.new
    publisher.register_message(:test_garbage)
    publisher.register_queue(:test_garbage)
    # purge the test queue
    publisher.purge(:test_garbage)
    # empty the dedup store
    publisher.deduplication_store.flushdb

    Beetle.config.servers = "localhost:5672"
    sub5672 = Beetle::Client.new
    sub5672.register_queue(:test_garbage)

    Beetle.config.servers = "localhost:5673"
    sub5673 = Beetle::Client.new
    sub5673.register_queue(:test_garbage)

    
    message5672 = nil
    sub5672.register_handler(:test_garbage) {|msg| 
      binding.pry
      message5672 = msg; 
      sub5672.stop_listening 
      sub5673.stop_listening 
    }

    message5673 = nil
    sub5673.register_handler(:test_garbage) {|msg| 
      binding.pry
      message5673 = msg; 
      sub5673.stop_listening 
    }

    published = publisher.publish(:test_garbage, 'bam', :redundant =>true) 

    sub5672.listen
    sub5673.listen
    publisher.stop_publishing
  
    assert_equal 2, published
    assert_equal "bam", message5672.data
    Beetle::DeduplicationStore::KEY_SUFFIXES.map{|suffix| 
      assert_equal false, publisher.deduplication_store.exists(message5672.msg_id, suffix)
    }
  end

end
