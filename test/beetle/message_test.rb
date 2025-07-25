require File.expand_path(File.dirname(__FILE__) + '/../test_helper')


module Beetle

  class RedeliveryInformationTest < Minitest::Test
    def logger
      Logger.new(File::NULL)
    end

    test "#redelivered is true if the message has been redelivered" do
      header = header_with_params({})
      header.stubs(:redelivered?).returns(true)

      m = Message.new("queue", header, 'foo', logger)

      assert m.redelivered?
    end

    test "#delivery_count returns the value of the x-delivery-count header if present" do
      header = header_with_params({ headers: { "x-delivery-count" => 5 } })
      m = Message.new("queue", header, 'foo', logger)

      assert_equal 5, m.delivery_count
    end

    test "#delivery_count returns nil if the x-delivery-count header is not present" do
      header = header_with_params()
      m = Message.new("queue", header, 'foo', logger)

      assert_nil m.delivery_count
    end
  end

  class EncodingTest < Minitest::Test
    def logger
      Logger.new(File::NULL)
    end

    test "an exception during decoding should be stored in the exception attribute" do
      header = stub_everything("raising header")
      m = Message.new("queue", header, 'foo', logger)
      assert_instance_of NoMethodError, m.exception
    end

    test "a message should encode/decode the message format version correctly" do
      header = header_with_params({})
      m = Message.new("queue", header, 'foo', logger)
      assert_equal Message::FORMAT_VERSION, m.format_version
    end

    test "a message should decode the timestamp" do
      Message.stubs(:now).returns(42)
      header = header_with_params()
      m = Message.new("queue", header, 'foo', logger)
      assert_equal 42, m.timestamp
    end

    test "a redundantly encoded message should have the redundant flag set on delivery" do
      header = header_with_params(:redundant => true)
      m = Message.new("queue", header, 'foo', logger)
      assert m.redundant?
      assert_equal(Message::FLAG_REDUNDANT, m.flags & Message::FLAG_REDUNDANT)
    end

    test "encoding a message with a specfied time to live should set an expiration time" do
      Message.stubs(:now).returns(25)
      header = header_with_params(:ttl => 17)
      m = Message.new("queue", header, 'foo', logger)
      assert_equal 42, m.expires_at
    end

    test "encoding a message should set the default expiration date if none is provided in the call to encode" do
      Message.stubs(:now).returns(1)
      header = header_with_params({})
      m = Message.new("queue", header, 'foo', logger)
      assert_equal 1 + Message::DEFAULT_TTL, m.expires_at
    end

    test "the publishing options should include both the beetle headers and the amqp params" do
      key = 'fookey'
      options = Message.publishing_options(:redundant => true, :key => key, :mandatory => true, :immediate => true, :persistent => true, :priority => 10)

      assert options[:mandatory]
      assert options[:immediate]
      assert options[:persistent]
      assert_equal key, options[:key]
      assert_equal "1", options[:headers][:flags]
      assert_equal 10, options[:priority]
    end

    test "the publishing options should silently ignore other parameters than the valid publishing keys" do
      options = Message.publishing_options(:redundant => true, :mandatory => true, :bogus => true)
      assert_equal "1", options[:headers][:flags]
      assert options[:mandatory]
      assert_nil options[:bogus]
    end

    test "the publishing options for a redundant message should include the uuid" do
      uuid = 'wadduyouwantfromme'
      Message.expects(:generate_uuid).returns(uuid)
      options = Message.publishing_options(:redundant => true)
      assert_equal uuid, options[:message_id]
    end

    test "the publishing options should include the timestamp" do
      Message.stubs(:now).returns(42)
      options = Message.publishing_options
      assert_equal 42, options[:timestamp]
    end

    test "the publishing options must only include string values" do
      options = Message.publishing_options(:redundant => true, :mandatory => true, :bogus => true)

      assert options[:headers].all? {|_, param| param.is_a?(String)}
    end

    test "the publishing options support adding custom headers" do
      options = Message.publishing_options(
        :redundant => true,
        :headers => {
          :sender_id => "SENDER_ID",
          :sender_action => "SENDER_ACTION"
        }
      )

      assert_equal "1", options[:headers][:flags]
      assert_equal "SENDER_ID", options[:headers][:sender_id]
      assert_equal "SENDER_ACTION", options[:headers][:sender_action]
    end

    test "the publishing options convert symbol values to strings" do
      options = Message.publishing_options(:headers => { :x => :foo })
      assert_equal "foo", options[:headers][:x]
    end

    test "the publishing options reject nil headers" do
      options = Message.publishing_options(:headers => { :x => nil })
      assert !options[:headers].has_key?(:x)
    end

    test "the publishing options don't change the passed in headers" do
      my_opts = {:headers => { :x => nil }}
      Message.publishing_options(my_opts)
      assert my_opts[:headers].has_key?(:x)
    end
  end

  class KeyManagementTest < Minitest::Test
    def logger
      Logger.new(File::NULL)
    end


    def setup
      @config = Configuration.new
      @config.redis_server = Beetle.config.redis_server
      @store = DeduplicationStore.new(@config)
      @store.flushdb
      @null_handler = Handler.create(lambda {|*args|}, logger)
    end

    test "should be able to extract msg_id from any key" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)
      @store.keys(message.msg_id).each do |key|
        assert_equal message.msg_id, @store.msg_id(key)
      end
    end

    test "successful processing of a non redundant message should delete all keys from the database" do
      header = header_with_params({})
      header.expects(:ack)
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)
      message.stubs(:simple?).returns(false)

      assert !message.expired?
      assert !message.redundant?

      message.process(@null_handler)
      keys = @store.keys(message.msg_id)
      assert_equal 0, @store.redis.exists(*keys)
    end

    test "successful processing of a non redundant message should delete all keys from the database (except the status key, which should be set to expire)" do
      @config.redis_status_key_expiry_interval = 1.minutes
      header = header_with_params({})
      header.expects(:ack)
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)
      message.stubs(:simple?).returns(false)

      assert !message.expired?
      assert !message.redundant?

      message.process(@null_handler)
      keys = @store.keys(message.msg_id)
      status_key = keys.shift
      assert @store.redis.exists?(status_key)
      assert @store.redis.ttl(status_key) <= @config.redis_status_key_expiry_interval
      assert_equal 0, @store.redis.exists(*keys)
    end

    test "successful processing of a redundant message twice should delete all keys from the database" do
      header = header_with_params({:redundant => true})
      header.expects(:ack).twice
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)

      assert !message.expired?
      assert message.redundant?
      assert !message.simple?

      message.process(@null_handler)
      message.process(@null_handler)

      keys = @store.keys(message.msg_id)
      assert_equal 0, @store.redis.exists(*keys)
    end

    test "successful processing of a redundant message twice should delete all keys from the database (except the status key, which should be set to expire)" do
      @config.redis_status_key_expiry_interval = 1.minutes
      header = header_with_params({:redundant => true})
      header.expects(:ack).twice
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)

      assert !message.expired?
      assert message.redundant?
      assert !message.simple?

      message.process(@null_handler)
      message.process(@null_handler)

      keys = @store.keys(message.msg_id)
      status_key = keys.shift
      assert @store.redis.exists?(status_key)
      assert @store.redis.ttl(status_key) <= @config.redis_status_key_expiry_interval
      assert_equal 0, @store.redis.exists(*keys)
    end

    test "successful processing of a redundant message once should insert all but the delay key and the exception count key into the database" do
      header = header_with_params({:redundant => true})
      header.expects(:ack)
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)

      assert !message.expired?
      assert message.redundant?

      message.process(@null_handler)

      assert @store.exists(message.msg_id, :status)
      assert @store.exists(message.msg_id, :expires)
      assert @store.exists(message.msg_id, :attempts)
      assert @store.exists(message.msg_id, :timeout)
      assert @store.exists(message.msg_id, :ack_count)
      assert !@store.exists(message.msg_id, :delay)
      assert !@store.exists(message.msg_id, :exceptions)
    end
  end

  class AckingTest < Minitest::Test
    def logger
      Logger.new(File::NULL)
    end

    def setup
      @store = DeduplicationStore.new
      @store.flushdb
      @null_handler = Handler.create(lambda {|*args|}, logger)
    end

    test "an expired message should be acked without calling the handler" do
      header = header_with_params(:ttl => -1)
      header.expects(:ack)
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)
      assert message.expired?

      processed = :no
      message.process(Handler.create(lambda {|*args| processed = true}, logger))
      assert_equal :no, processed
    end

    test "a delayed message should not be acked and the handler should not be called" do
      header = header_with_params()
      header.expects(:ack).never
      message = Message.new("somequeue", header, 'foo', logger, :attempts => 2, :store => @store)
      message.set_delay!
      assert !message.key_exists?
      assert message.delayed?

      processed = :no
      message.process(Handler.create(lambda {|*args| processed = true}, logger))
      assert_equal :no, processed
    end

    test "acking a non redundant message should remove the ack_count key" do
      header = header_with_params({})
      header.expects(:ack)
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)

      message.process(@null_handler)
      assert !message.redundant?
      assert !@store.exists(message.msg_id, :ack_count)
    end

    test "a redundant message should be acked after calling the handler" do
      header = header_with_params({:redundant => true})
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)

      message.expects(:ack!)
      assert message.redundant?
      message.process(@null_handler)
    end

    test "acking a redundant message should increment the ack_count key" do
      header = header_with_params({:redundant => true})
      header.expects(:ack)
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)

      assert_nil @store.get(message.msg_id, :ack_count)
      message.process(@null_handler)
      assert message.redundant?
      assert_equal "1", @store.get(message.msg_id, :ack_count)
    end

    test "acking a redundant message twice should remove the ack_count key" do
      header = header_with_params({:redundant => true})
      header.expects(:ack).twice
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)

      message.process(@null_handler)
      message.process(@null_handler)
      assert message.redundant?
      assert !@store.exists(message.msg_id, :ack_count)
    end

  end

  class FreshMessageTest < Minitest::Test
    def logger
      Logger.new(File::NULL)
    end

    def setup
      @store = DeduplicationStore.new
      @store.flushdb
    end

    test "processing a fresh message sucessfully should first run the handler and then ack it" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :attempts => 2, :store => @store)
      assert !message.attempts_limit_reached?

      handler = mock("handler")
      s = sequence("s")
      handler.expects(:pre_process).with(message).in_sequence(s)
      handler.expects(:call).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      assert_equal RC::OK, message.process(handler)
    end

    test "after processing a redundant fresh message successfully the ack count should be 1 and the status should be completed" do
      header = header_with_params({:redundant => true})
      message = Message.new("somequeue", header, 'foo', logger, :timeout => 10.seconds, :store => @store)
      assert !message.attempts_limit_reached?
      assert message.redundant?

      proc = mock("proc")
      s = sequence("s")
      proc.expects(:call).in_sequence(s)
      message.expects(:completed!).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      assert_equal RC::OK, message.__send__(:process_internal, proc)
      assert_equal "1", @store.get(message.msg_id, :ack_count)
    end

  end

  class SimpleMessageTest < Minitest::Test
    def logger
      Logger.new(File::NULL)
    end

    def setup
      @config = Configuration.new
      @config.redis_server = Beetle.config.redis_server
      @store = DeduplicationStore.new(@config)
      @store.flushdb
    end

    test "when processing a simple message, ack should follow calling the handler" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :attempts => 1, :store => @store)

      handler = mock("handler")
      s = sequence("s")
      handler.expects(:pre_process).with(message).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      handler.expects(:call).in_sequence(s)
      assert_equal RC::OK, message.process(handler)
    end

    test "when processing a simple message, RC::AttemptsLimitReached should be returned if the handler crashes" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :attempts => 1, :store => @store)

      handler = mock("handler")
      s = sequence("s")
      handler.expects(:pre_process).with(message).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      e = Exception.new("ohoh")
      handler.expects(:call).in_sequence(s).raises(e)
      handler.expects(:process_exception).with(e).in_sequence(s)
      handler.expects(:process_failure).with(RC::AttemptsLimitReached).in_sequence(s)
      assert_equal RC::AttemptsLimitReached, message.process(handler)
    end

    test "when processing a simple message, the handler should be executed only once if status keys are used" do
      @config.redis_status_key_expiry_interval = 1.minute
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :attempts => 1, :store => @store)

      handler = mock("handler")
      s = sequence("s")
      handler.expects(:pre_process).with(message).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      handler.expects(:call).in_sequence(s)
      assert_equal RC::OK, message.process(handler)

      handler2 = mock("handler")
      s2 = sequence("s2")
      handler2.expects(:pre_process).with(message).in_sequence(s2)
      header.expects(:ack).in_sequence(s2)
      handler2.expects(:call).in_sequence(s2).never
      assert_equal RC::OK, message.process(handler2)
    end

  end

  class HandlerCrashTest < Minitest::Test
    def logger
      Logger.new(File::NULL)
    end

    def setup
      @store = DeduplicationStore.new
      @store.flushdb
    end

    test "a message should not be acked if the handler crashes and the exception limit has not been reached" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :delay => 42, :timeout => 10.seconds, :exceptions => 1, :store => @store)
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?
      assert !message.timed_out?

      proc = lambda {|*args| raise "crash"}
      message.stubs(:now).returns(10)
      message.expects(:completed!).never
      header.expects(:ack).never
      assert_equal RC::HandlerCrash, message.__send__(:process_internal, proc)
      assert !message.completed?
      assert_equal "1", @store.get(message.msg_id, :exceptions)
      assert_equal "0", @store.get(message.msg_id, :timeout)
      assert_equal "52", @store.get(message.msg_id, :delay)
    end

    test "a message should delete the mutex before resetting the timer if attempts and exception limits haven't been reached" do
      Message.stubs(:now).returns(9)
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :delay => 42, :timeout => 10.seconds, :exceptions => 1, :store => @store)
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?
      assert !@store.get(message.msg_id, :mutex)
      assert !message.timed_out?

      proc = lambda {|*args| raise "crash"}
      message.expects(:delete_mutex!)
      message.stubs(:now).returns(10)
      message.expects(:completed!).never
      header.expects(:ack).never
      assert_equal RC::HandlerCrash, message.__send__(:process_internal, proc)
    end

    test "a message should be acked if the handler crashes and the exception limit has been reached" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :timeout => 10.seconds, :attempts => 2, :store => @store)
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?
      assert !message.timed_out?
      assert !message.simple?

      proc = lambda {|*args| raise "crash"}
      s = sequence("s")
      message.expects(:completed!).once
      header.expects(:ack)
      assert_equal RC::ExceptionsLimitReached, message.__send__(:process_internal, proc)
    end

    class RegisteredException < StandardError; end

    test "a message should not be acked if the handler crashes and the exception has been registered" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :timeout => 10.seconds, :exceptions => 2,
                            :retry_on => [RegisteredException], :store => @store)
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?
      assert !message.timed_out?
      assert !message.simple?
      assert message.exception_accepted? # @exception yet nil, hence 'accepted'

      proc = lambda {|_| raise RegisteredException, "crash"}
      message.expects(:completed!).never
      header.expects(:ack).never
      assert_equal RC::HandlerCrash, message.__send__(:process_internal, proc)
    end

    class OtherException < StandardError; end

    test "a message should be acked if the handler crashes and the exception has not been registered" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :timeout => 10.seconds, :exceptions => 2,
                            :retry_on => [RegisteredException], :store => @store)
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?
      assert !message.timed_out?
      assert !message.simple?
      assert message.exception_accepted? # @exception yet nil, hence 'accepted'

      proc = lambda {|_| raise OtherException, "crash"}
      message.expects(:completed!).once
      header.expects(:ack)
      assert_equal RC::ExceptionNotAccepted, message.__send__(:process_internal, proc)
    end

    test "a message should be acked if the handler crashes and the attempts limit has been reached" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :timeout => 10.seconds, :attempts => 2, :store => @store)
      message.increment_execution_attempts!
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?
      assert !message.timed_out?

      proc = lambda {|*args| raise "crash"}
      message.expects(:completed!).once
      header.expects(:ack)
      assert_equal RC::AttemptsLimitReached, message.__send__(:process_internal, proc)
    end

  end

  class SeenMessageTest < Minitest::Test
    def logger
      Logger.new(File::NULL)
    end

    def setup
      @store = DeduplicationStore.new
      @store.flushdb
    end

    test "a message with a decoding error should not be processed at all, but it should be acked" do
      header = {}
      message = Message.new("somequeue", header, 'foo', logger)
      assert message.exception

      proc = mock("proc")
      proc.expects(:call).never
      message.expects(:ack!)
      assert_equal RC::DecodingError, message.__send__(:process_internal, proc)
    end

    test "a message with a preprocessing error set should not be processed at all, but it should be acked" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger)
      message.instance_eval { @pre_exception = StandardError.new("shoo") }

      proc = mock("proc")
      proc.expects(:call).never
      message.expects(:ack!)
      assert_equal RC::PreprocessingError, message.__send__(:process_internal, proc)
    end

    test "a completed existing message should be just acked and not run the handler" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :attempts => 2, :store => @store)
      assert !message.key_exists?
      message.completed!
      assert message.completed?

      proc = mock("proc")
      header.expects(:ack)
      proc.expects(:call).never
      assert_equal RC::OK, message.__send__(:process_internal, proc)
    end

    test "an incomplete, delayed existing message should be processed later" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :delay => 10.seconds, :attempts => 2, :store => @store)
      assert !message.key_exists?
      assert !message.completed?
      message.set_delay!
      assert message.delayed?

      proc = mock("proc")
      header.expects(:ack).never
      proc.expects(:call).never
      assert_equal RC::Delayed, message.__send__(:process_internal, proc)
      assert message.delayed?
      assert !message.completed?
    end

    test "an incomplete, undelayed, not yet timed out, existing message should be processed later" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :timeout => 10.seconds, :attempts => 2, :store => @store)
      assert !message.key_exists?
      assert !message.completed?
      assert !message.delayed?
      message.set_timeout!
      assert !message.timed_out?

      proc = mock("proc")
      header.expects(:ack).never
      proc.expects(:call).never
      assert_equal RC::HandlerNotYetTimedOut, message.__send__(:process_internal, proc)
      assert !message.delayed?
      assert !message.completed?
      assert !message.timed_out?
    end

    test "an incomplete, undelayed, not yet timed out, existing message which has reached the handler execution attempts limit should be acked and not run the handler" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :attempts => 2, :store => @store)
      message.increment_execution_attempts!
      assert !message.key_exists?
      assert !message.completed?
      assert !message.delayed?
      message.timed_out!
      assert message.timed_out?

      assert !message.attempts_limit_reached?
      message.attempts_limit.times {message.increment_execution_attempts!}
      assert message.attempts_limit_reached?

      proc = mock("proc")
      header.expects(:ack)
      proc.expects(:call).never
      assert_equal RC::AttemptsLimitReached, message.send(:process_internal, proc)
    end

    test "an incomplete, undelayed, timed out, existing message which has reached the exceptions limit should be acked and not run the handler" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :attempts => 2, :store => @store)
      message.increment_execution_attempts!
      assert !message.key_exists?
      assert !message.completed?
      assert !message.delayed?
      message.timed_out!
      assert message.timed_out?
      assert !message.attempts_limit_reached?
      message.increment_exception_count!
      assert message.exceptions_limit_reached?

      proc = mock("proc")
      header.expects(:ack)
      proc.expects(:call).never
      assert_equal RC::ExceptionsLimitReached, message.send(:process_internal, proc)
    end

    test "an incomplete, undelayed, timed out, existing message should be processed again if the mutex can be aquired" do
      header = header_with_params({:redundant => true})
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)
      assert !message.key_exists?
      assert !message.completed?
      assert !message.delayed?
      message.timed_out!
      assert message.timed_out?
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?

      proc = mock("proc")
      s = sequence("s")
      message.expects(:set_timeout!).in_sequence(s)
      proc.expects(:call).in_sequence(s)
      header.expects(:ack).in_sequence(s)
      assert_equal RC::OK, message.__send__(:process_internal, proc)
      assert message.completed?
    end

    test "an incomplete, undelayed, timed out, existing message should not be processed again if the mutex cannot be aquired" do
      header = header_with_params({:redundant => true})
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)
      assert !message.key_exists?
      assert !message.completed?
      assert !message.delayed?
      message.timed_out!
      assert message.timed_out?
      assert !message.attempts_limit_reached?
      assert !message.exceptions_limit_reached?
      message.aquire_mutex!
      assert @store.exists(message.msg_id, :mutex)

      proc = mock("proc")
      proc.expects(:call).never
      header.expects(:ack).never
      assert_equal RC::MutexLocked, message.__send__(:process_internal, proc)
      assert !message.completed?
      assert !@store.exists(message.msg_id, :mutex)
    end

  end

  class ProcessingTest < Minitest::Test
    def logger
      Logger.new(File::NULL)
    end

    def setup
      @store = DeduplicationStore.new
      @store.flushdb
    end

    test "processing a message catches internal exceptions risen by process_internal and returns an internal error" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :store => @store)
      message.expects(:process_internal).raises(Exception.new("this is expected"))
      handler = Handler.new
      handler.expects(:process_exception).never
      handler.expects(:process_failure).never
      assert_equal RC::InternalError, message.process(1)
    end

    test "processing a message with a crashing processor calls the processors exception handler and returns an internal error" do
      header = header_with_params({})
      message = Message.new("somequeue", header, 'foo', logger, :exceptions => 1, :store => @store)
      errback = lambda{|*args|}
      exception = Exception.new
      action = lambda{|*args| raise exception}
      handler = Handler.create(action, logger, :errback => errback)
      handler.expects(:process_exception).with(exception).once
      handler.expects(:process_failure).never
      result = message.process(handler)
      assert_equal RC::HandlerCrash, result
      assert result.reject?
      assert !result.failure?
    end

    test "processing a message with a crashing processor calls the processors exception handler and failure handler if the attempts limit has been reached" do
      header = header_with_params({})
      header.expects(:ack)
      message = Message.new("somequeue", header, 'foo', logger, :attempts => 2, :store => @store)
      message.increment_execution_attempts!
      errback = mock("errback")
      failback = mock("failback")
      exception = Exception.new
      action = lambda{|*args| raise exception}
      handler = Handler.create(action, logger, :errback => errback, :failback => failback)
      errback.expects(:call).once
      failback.expects(:call).once
      result = message.process(handler)
      assert_equal RC::AttemptsLimitReached, result
      assert !result.reject?
      assert result.failure?
    end

    test "processing a message with a crashing processor calls the processors exception handler and failure handler if the exceptions limit has been reached" do
      header = header_with_params({})
      header.expects(:ack)
      message = Message.new("somequeue", header, 'foo', logger, :attempts => 2, :store => @store)
      errback = mock("errback")
      failback = mock("failback")
      exception = Exception.new
      action = lambda{|*args| raise exception}
      handler = Handler.create(action, logger, :errback => errback, :failback => failback)
      errback.expects(:call).once
      failback.expects(:call).once
      result = message.process(handler)
      assert_equal RC::ExceptionsLimitReached, result
      assert !result.reject?
      assert result.failure?
    end

  end

  class HandlerTimeoutTest < Minitest::Test
    def logger
      Logger.new(File::NULL)
    end

    def setup
      @store = DeduplicationStore.new
      @store.flushdb
    end

    test "a handler running longer than the specified timeout should be aborted (when given a float timeout number)" do
      header = header_with_params({})
      header.expects(:ack)
      message = Message.new("somequeue", header, 'foo', logger, :timeout => 0.1, :attempts => 2, :store => @store)
      action = lambda{|*args| while true; end}
      handler = Handler.create(action, logger)
      result = message.process(handler)
      assert_equal RC::ExceptionsLimitReached, result
    end

    test "a handler running longer than the specified timeout should be aborted (when using active_support seconds)" do
      header = header_with_params({})
      header.expects(:ack)
      message = Message.new("somequeue", header, 'foo', logger, :timeout => 1.seconds, :attempts => 2, :store => @store)
      action = lambda{|*args| while true; end}
      handler = Handler.create(action, logger)
      result = message.process(handler)
      assert_equal RC::ExceptionsLimitReached, result
    end

  end

  class MySQLFailoverTest < Minitest::Test
    require "active_record"

    def logger
      Logger.new(File::NULL)
    end

    def setup
      @store = DeduplicationStore.new
      @store.flushdb

      ActiveRecord::Base.establish_connection(
        adapter:  "mysql2",
        username: "root",
        encoding: "utf8",
        host: ENV['MYSQL_HOST'] || "127.0.0.1",
        port: (ENV['MYSQL_PORT'] || 3306).to_i
      )
    end

    test "a handler that drops a MySQL query ensures the connection still works" do
      header = header_with_params({})
      header.expects(:ack)
      message = Message.new("somequeue", header, "foo", logger, :timeout => 1.second, :attempts => 2, :store => @store)
      action = lambda do |*args|
        # the timeout should stop the query before it finishes.
        ActiveRecord::Base.connection.execute("select sleep(6);")
      end
      handler = Handler.create(action, logger)
      result = message.process(handler)
      assert_equal RC::ExceptionsLimitReached, result

      # second message should process without problems
      second_header = header_with_params({})
      second_header.expects(:ack)
      second_message = Message.new("somequeue", second_header, "foo2", logger, :timeout => 2.seconds, :attempts => 1, :store => @store)
      second_action = lambda do |*args|
        ActiveRecord::Base.connection.execute("select 1;")
      end
      second_handler = Handler.create(second_action, logger)
      second_result = second_message.process(second_handler)
      assert_equal RC::OK, second_result
    end
  end

  class RoutingKeyTest < Minitest::Test
    def logger
      Logger.new(File::NULL)
    end

    test "returns the routing key" do
      header = header_with_params({})
      header.stubs(:routing_key).returns("foo")
      message = Message.new("somequeue", header, "", logger)
      assert_equal "foo", message.routing_key
      assert_equal "foo", message.key # alias
    end

    test "returns the routing key for a dead lettered message" do
      header = header_with_params({})
      header.stubs(:routing_key).returns("bar")
      header.attributes.merge!(headers: {"x-death" => [{"routing-keys" => ["foo"]}]})

      message = Message.new("somequeue", header, "", logger)
      assert_equal "foo", message.routing_key
      assert_equal "foo", message.key # alias
    end

  end
end
