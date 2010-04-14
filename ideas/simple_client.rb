# The simplest case
client.register_message(:something_happened)                  # => key: something_happened

# with options
client.register_message(:

####################
# Message Grouping #
####################

client.register_message(:delete_something, :group => :jobs)   # => key: jobs.delete_something
client.register_message(:create_something, :group => :jobs)   # => key: jobs.create_something

# You can register a handler for a message group
client.register_handler(JobsHandler, :group => :jobs)         # bind queue with: jobs.*

# And still register on single messages
client.register_handler(DeletedJobHandler, :delete_something) # bind queue with: *.delete_something

######################
# Handler Definition #
######################

# With a Handler class that implements .process(message)
client.register_handler(MyProcessor, :something_happened)                    # => queue: my_processor

# With a String / Symbol and a block
client.register_handler("Other Processor", :delete_something, :something_happened) lambda { |message| foobar(message) } # => queue: other_processor, bound with: *.delete_something and *.something_happened

# With extra parameters
client.register_handler(VeryImportant, :delete_something, :immediate => true) # queue: very_important, :immediate => true

###################################
# Wiring, Subscribing, Publishing #
###################################
client.wire! # => all the binding magic happens

client.subscribe

client.publish(:delete_something, 'payload')

__END__

Whats happening when wire! is called? (pseudocode)
1. all the messages are registered
     messages = [{:name => :delete_something, :group => :jobs, :bound => false}, {:name => :something_happened, :bound => false}]
2. all the queues for the handlers are created and bound...
     my_processor_queue = queue(:my_processor).bind(exchange, :key => '*.something_happened')
     jobs_handler_queue = queue(:jobs_handler).bind(exchange, :key => 'jobs.*')
     handlers_with_queues = [[jobs_handler_queue, JobsHandler], [my_processor_queue, block_or_class]]
3. every handler definition binds a queue for the handler to a list of messages and marks the message as bound.
4. If in the end a message isn't bound to a queue at least once, an exception is raised

Exceptions will be thrown if:
* after all m
