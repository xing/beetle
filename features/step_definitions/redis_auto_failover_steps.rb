Given /^a redis server "([^\"]*)" exists as master$/ do |redis_name|
  RedisTestServer[redis_name].start
  RedisTestServer[redis_name].master
end

Given /^a redis server "([^\"]*)" exists as slave of "([^\"]*)"$/ do |redis_name, redis_master_name|
  RedisTestServer[redis_name].start
  RedisTestServer[redis_name].slave_of(RedisTestServer[redis_master_name].port)
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
  assert RedisTestServer[redis_name].master?, "#{redis_name} is not a master"
end

Then /^the redis master of "([^\"]*)" should be "([^\"]*)"$/ do |redis_configuration_client_name, redis_name|
  master_file = redis_master_file_path(redis_configuration_client_name)
  server_info = File.read(master_file).chomp
  assert_equal RedisTestServer[redis_name].ip_with_port, server_info
end

Given /^a beetle handler using the redis-master file from "([^\"]*)" exists$/ do |redis_configuration_client_name|
  master_file = redis_master_file_path(redis_configuration_client_name)
  `ruby features/support/beetle_handler start -- --redis-master-file=#{master_file}`
  assert File.exist?(master_file), "file #{master_file} does not exist"
end

Then /^the redis master of the beetle handler should be "([^\"]*)"$/ do |redis_name|
  Beetle.config.servers = "localhost:5672, localhost:5673" # rabbitmq
  Beetle.config.logger.level = Logger::INFO
  client = Beetle::Client.new
  client.register_queue(:echo)
  client.register_message(:echo)
  assert_equal RedisTestServer[redis_name].ip_with_port, client.rpc(:echo, 'nil').second
end

Given /^redis server "([^\"]*)" is down for less seconds than the retry timeout for the redis master check$/ do |redis_name|
  RedisTestServer[redis_name].restart(1)
end

Then /^the role of redis server "([^\"]*)" should still be "([^\"]*)"$/ do |redis_name, role|
  RedisTestServer[redis_name].__send__ "#{role}?"
end

Then /^the redis master of "([^\"]*)" should still be "([^\"]*)"$/ do |redis_configuration_client_name, redis_name|
  master_file = redis_master_file_path(redis_configuration_client_name)
  assert_equal RedisTestServer[redis_name].ip_with_port, File.read(master_file).chomp
end

Then /^the redis master of "([^\"]*)" should be undefined$/ do |redis_configuration_client_name|
  master_file = redis_master_file_path(redis_configuration_client_name)
  assert_equal "", File.read(master_file).chomp
end

Given /^the first redis configuration client is not able to send the client_invalidated message$/ do
  # we kill the redis configuration process brutally, so that it cannot send an offline message before exit
  Process.kill("KILL", first_redis_configuration_client_pid)
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
