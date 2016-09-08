# consume_many_messages_and_shutdown_randomly.rb
# this example excercises the shutdown sequence and tests whether
# messages are handled more than once due to the shutdown
#
# ! check the examples/README.rdoc for information on starting your redis/rabbit !
#
# use it like so:
#
# while ruby consume_many_messages_and_shutdown_randomly.rb; do echo "no duplicate found yet"; done
#
# if the loop stops, a duplicate has been found.
# you can stop this process by sending an interrupt signal

trap("INT"){ puts "ignoring interrupt, please wait" }

require "rubygems"
require File.expand_path("../lib/beetle", File.dirname(__FILE__))

# set Beetle log level to info, less noisy than debug
Beetle.config.logger.level = Logger::INFO
# excercise prefetch_count setting
Beetle.config.prefetch_count = 100

# setup client
client = Beetle::Client.new
client.register_queue(:test)
client.register_message(:test)

# create a redis instance with a different database
redis = Redis.new(:db => 7)

exit_code = 0

# register our handler to the message, check out the message.rb for more stuff you can get from the message object
client.register_handler(:test) do |message|
  uuid = message.uuid
  if redis.incr(uuid) > 1
    exit_code = 1
    puts "\n\nRECEIVED A MESSAGE twice: #{uuid}\n\n"
    client.stop_listening
  end
end

# start listening
# this starts the event machine event loop using EM.run
# the block passed to listen will be yielded as the last step of the setup process
client.listen do
  trap("TERM"){ client.stop_listening }
  trap("INT"){ exit_code = 1; client.stop_listening }
  # start a thread which randomly kills us
  Thread.new do
    sleep(2 + rand)
    Process.kill("TERM", $$)
  end
  puts "trying to detect duplicates"
end

exit exit_code
