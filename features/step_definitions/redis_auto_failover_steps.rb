Given /^a redis server "([^\"]*)" exists as master$/ do |redis_name|
  RedisTestServer[redis_name].start
  RedisTestServer[redis_name].master
end

Given /^a redis server "([^\"]*)" exists as slave of "([^\"]*)"$/ do |redis_name, redis_master_name|
  RedisTestServer[redis_name].start
  RedisTestServer[redis_name].slave_of(RedisTestServer[redis_master_name].port) 
end

Given /^a redis configuration server using redis servers "([^\"]*)" exists$/ do |redis_server_names|
  redis_servers_string = redis_server_names.split(",").map do |redis_name|
    RedisTestServer[redis_name].ip_with_port
  end.join(",")
  `ruby bin/redis_configuration_server --redis-servers=#{redis_servers_string} --redis-retry-timeout 1 > /dev/null 2>&1 &`
end

Given /^a redis configuration client "([^\"]*)" using redis servers "([^\"]*)" exists$/ do |redis_configuration_client_name, redis_server_names|
  redis_servers_string = redis_server_names.split(",").map do |redis_name|
    RedisTestServer[redis_name].ip_with_port
  end.join(",")
  fork {`ruby bin/redis_configuration_client --redis-servers=#{redis_servers_string} > /dev/null 2>&1 &`}
end

Given /^redis server "([^\"]*)" is down$/ do |redis_name|
  RedisTestServer[redis_name].stop
end

Given /^the retry timeout for the redis master check is reached$/ do
  sleep 5
end

Then /^the role of redis server "([^\"]*)" should be "([^\"]*)"$/ do |arg1, arg2|
  pending # express the regexp above with the code you wish you had
end

Then /^the redis master of "([^\"]*)" should be "([^\"]*)"$/ do |arg1, arg2|
  pending # express the regexp above with the code you wish you had
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