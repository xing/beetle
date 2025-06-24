require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle

  class Foobar < Handler
    def process
    end
  end

  class SubFoobar < Foobar
    def process
      raise RuntimeError
    end
  end

  class HandlerTest < Minitest::Test

    def logger 
      @logger ||= Logger.new(File::NULL)
    end

    test "should allow using a block as a callback" do
      test_var = false
      handler = Handler.create(lambda {|message| test_var = message}, logger)
      handler.call(true)
      assert test_var
    end

    test "should allow using a subclass of a handler as a callback" do
      handler = Handler.create(Foobar, logger)
      Foobar.any_instance.expects(:process)
      handler.call('some_message')
    end

    test "should allow using an instance of a subclass of handler as a callback" do
      handler = Handler.create(Foobar.new, logger)
      Foobar.any_instance.expects(:process)
      handler.call('some_message')
    end

    test "should set the instance variable message to the received message" do
      handler = Handler.create(Foobar, logger)
      assert_nil handler.message
      handler.call("message received")
      assert_equal "message received", handler.message
    end

    test "should call the error method with the exception if no error callback has been given" do
      handler = Handler.create(SubFoobar, logger)
      e = Exception.new
      handler.expects(:error).with(e)
      handler.process_exception(e)
    end

    test "should call the given error callback with the exception" do
      mock = mock('error handler')
      e = Exception.new
      mock.expects(:call).with('message', e)
      handler = Handler.create(lambda {}, logger, :errback => mock)
      handler.instance_variable_set(:@message, 'message')
      handler.process_exception(e)
    end

    test "should call the failure method with the exception if no failure callback has been given" do
      handler = Handler.create(SubFoobar, logger)
      handler.expects(:failure).with(1)
      handler.process_failure(1)
    end

    test "should call the given failure callback with the result" do
      mock = mock('failure handler')
      mock.expects(:call).with('message', 1)
      handler = Handler.create(lambda {}, logger, {:failback => mock})
      handler.instance_variable_set(:@message, 'message')
      handler.process_failure(1)
    end

    test "logger should point to the Beetle.config.logger if none specified" do
      handler = Handler.create(Foobar)
      
      assert_equal Beetle.config.logger, handler.logger
    end

    test "default implementation of error and process and failure and completed should not crash" do
      handler = Handler.create(lambda {}, logger)
      handler.process
      handler.error(StandardError.new('barfoo'))
      handler.failure('razzmatazz')
      handler.completed
    end

    test "should silently rescue exceptions in the process_exception call" do
      mock = mock('error handler')
      e = Exception.new
      mock.expects(:call).with('message', e).raises(Exception)
      handler = Handler.create(lambda {} , logger, :errback => mock)
      handler.instance_variable_set(:@message, 'message')
      assert_nothing_raised {handler.process_exception(e)}
    end

    test "should silently rescue exceptions in the process_failure call" do
      mock = mock('failure handler')
      mock.expects(:call).with('message', 1).raises(Exception)
      handler = Handler.create(lambda {}, logger, :failback => mock)
      handler.instance_variable_set(:@message, 'message')
      assert_nothing_raised {handler.process_failure(1)}
    end

    test "should silently rescue exceptions in the processing_completed call" do
      handler = Handler.create(lambda {|m|}, logger)
      handler.expects(:completed).raises(Exception)
      handler.call(mock("message"))
      assert_nothing_raised {handler.processing_completed}
    end

    test "should not invoke completed method when the hander was never called" do
      handler = Handler.create(lambda {}, logger)
      handler.expects(:completed).never
      assert_nothing_raised {handler.processing_completed}
    end

  end
end
