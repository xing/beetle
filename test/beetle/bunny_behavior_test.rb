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
end
