Given /^a redis server "([^\"]*)" exists as master$/ do |redis_name|
  RedisTestServer[redis_name].start
  RedisTestServer[redis_name].master
end

Given /^a redis server "([^\"]*)" exists as slave of "([^\"]*)"$/ do |redis_name, redis_master_name|
  RedisTestServer[redis_name].start
  RedisTestServer[redis_name].slave_of(RedisTestServer[redis_master_name].port)
  sleep 2 # master-slave sync may take a while
end

Given /^a redis configuration server using redis servers "([^\"]*)" exists$/ do |redis_names|
  redis_servers_string = redis_names.split(",").map do |redis_name|
    RedisTestServer[redis_name].ip_with_port
  end.join(",")
  `ruby bin/redis_configuration_server start -- --redis-servers=#{redis_servers_string} --redis-retry-timeout 1`
end

Given /^a redis configuration client "([^\"]*)" using redis servers "([^\"]*)" exists$/ do |redis_configuration_client_name, redis_names|
  redis_servers_string = redis_names.split(",").map do |redis_name|
    RedisTestServer[redis_name].ip_with_port
  end.join(",")
  `ruby bin/redis_configuration_client start -- --redis-servers=#{redis_servers_string} --redis-master-file=#{redis_master_file_path(redis_configuration_client_name)} --id #{redis_configuration_client_name}`
end

Given /^redis server "([^\"]*)" is down$/ do |redis_name|
  RedisTestServer[redis_name].stop
end

Given /^the retry timeout for the redis master check is reached$/ do
  sleep 5
end

Then /^the role of redis server "([^\"]*)" should be master$/ do |redis_name|
  assert RedisTestServer[redis_name].master?
end

Then /^the redis master of "([^\"]*)" should be "([^\"]*)"$/ do |redis_configuration_client_name, redis_name|
  assert_equal RedisTestServer[redis_name].ip_with_port, File.read(redis_master_file_path(redis_configuration_client_name)).chomp
end

Given /^a beetle handler using the redis-master file from "([^\"]*)" exists$/ do |redis_configuration_client_name|
  `ruby features/support/beetle_handler start -- --redis-master-file=#{redis_master_file_path(redis_configuration_client_name)}`
end

Then /^the redis master of the beetle handler should be "([^\"]*)"$/ do |redis_name|
  Beetle.config.servers = "localhost:5672, localhost:5673" # rabbitmq
  Beetle.config.logger.level = Logger::INFO
  client = Beetle::Client.new
  client.register_queue(:echo)
  client.register_message(:echo)
  assert_equal RedisTestServer[redis_name].ip_with_port, client.rpc(:echo, 'nil').second
end

Given /^redis server "([^\"]*)" is down for less seconds than the retry timeout for the redis master check$/ do |arg1|
  pending # express the regexp above with the code you wish you had
end

Then /^the role of "([^\"]*)" should still be "([^\"]*)"$/ do |arg1, arg2|
  pending # express the regexp above with the code you wish you had
end

Then /^the redis master of "([^\"]*)" should still be "([^\"]*)"$/ do |arg1, arg2|
  pending # express the regexp above with the code you wish you had
end

Given /^a reconfiguration round is in progress$/ do
  pending # express the regexp above with the code you wish you had
end

Then /^the redis master of "([^\"]*)" should be nil$/ do |arg1|
  pending # express the regexp above with the code you wish you had
end

Given /^the retry timeout for the redis master determination is reached$/ do
  pending # express the regexp above with the code you wish you had
end

Given /^the redis configuration client process "([^\"]*)" is disconnected from the system queue$/ do |arg1|
  pending # express the regexp above with the code you wish you had
end