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

  class HandlerTest < Test::Unit::TestCase

    test "should allow using a block as a callback" do
      test_var = false
      handler = Handler.create(lambda {|message| test_var = message})
      handler.call(true)
      assert test_var
    end
    
    test "should allow using a subclass of a handler as a callback" do
      handler = Handler.create(Foobar)
      Foobar.any_instance.expects(:process)
      handler.call('some_message')
    end
    
    test "should allow using an instance of a subclass of handler as a callback" do
      handler = Handler.create(Foobar.new)
      Foobar.any_instance.expects(:process)
      handler.call('some_message')
    end
    
    test "should set the instance variable message to the received message" do
      handler = Handler.create(Foobar)
      assert_nil handler.message
      handler.call("message received")
      assert_equal "message received", handler.message
    end
    
    test "should call the error method with the exception if no error callback has been given" do
      handler = Handler.create(SubFoobar)
      e = Exception.new
      handler.expects(:error).with(e)
      handler.process_exception(e)
    end
    
    test "should call the given error callback with the exception" do
      mock = mock('error handler')
      e = Exception.new
      mock.expects(:call).with('message', e)
      handler = Handler.create(lambda {}, {:errback => mock})
      handler.instance_variable_set(:@message, 'message')
      handler.process_exception(e)
    end
    
    test "logger should point to the Beetle.config.logger" do
      handler = Handler.create(Foobar)
      assert_equal Beetle.config.logger, handler.logger
      assert_equal Beetle.config.logger, Handler.logger
    end
    
    test "default implementation of error and process should not crash" do
      handler = Handler.create(lambda {})
      handler.process('foobar')
      handler.error('barfoo')
    end
    
    test "should silently rescue exceptions in the process_exception call" do
      mock = mock('error handler')
      e = Exception.new
      mock.expects(:call).with('message', e).raises(RuntimeError)
      handler = Handler.create(lambda {}, {:errback => mock})
      handler.instance_variable_set(:@message, 'message')
      assert_nothing_raised {handler.process_exception(e)}
    end
    
    
  end
end
