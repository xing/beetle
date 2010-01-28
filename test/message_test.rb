require File.expand_path(File.dirname(__FILE__) + '/test_helper')

module Bandersnatch
  class EncodingTest < Test::Unit::TestCase
    test "a message should encode/decode the message format version correctly" do
      body = Message.encode("12345")
      header = mock("header")
      m = Message.new("server", header, body)
      assert_equal Message::FORMAT_VERSION, m.format_version
    end

    test "a message with uuid should have a uuid and the uuid flag set" do
      body = Message.encode("12345", :with_uuid => true)
      header = mock("header")
      m = Message.new("server", header, body)
      assert m.has_uuid?
      assert_equal(Message::FLAG_UUID, m.flags & Message::FLAG_UUID)
    end

    test "a message without uuid should have a nil uuid and the uuid flag not set" do
      body = Message.encode("12345")
      header = mock("header")
      m = Message.new("server", header, body)
      assert !m.has_uuid?
      assert_equal(0, m.flags & Message::FLAG_UUID)
    end

    test "encoding a message should set an expiration date" do
      Message.expects(:ttl_to_expiration_time).with(17).returns(42)
      body = Message.encode("12345", :ttl => 17)
      header = mock("header")
      m = Message.new("server", header, body)
      assert_equal 42, m.expires_at
    end

    test "encoding a message should set the default expiration date if noe is provided in the call to encode" do
      Message.expects(:ttl_to_expiration_time).with(Message::DEFAULT_TTL).returns(42)
      body = Message.encode("12345")
      header = mock("header")
      m = Message.new("server", header, body)
      assert_equal 42, m.expires_at
    end
  end

  class IdInsertionTest < Test::Unit::TestCase
    def setup
      Message.redis.flushdb
    end

    test "the database should not be checked if the message has no uuid" do
      body = Message.encode('my message', :with_uuid => false)
      message = Message.new("server", {}, body)

      message.expects(:new_in_queue?).never
      message.insert_id('somequeue')
    end

    # test "inserting a messages uuid for the same queu into the database should fail the second time" do
    #   body = Message.encode('my message', :with_uuid => true)
    #   message = Message.new('server', {}, body)
    # 
    #   assert message.insert_id('somequeue')
    #   assert !message.insert_id('somequeue')
    # end
  end
end