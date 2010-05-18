Feature: Redis auto failover
  In order to eliminate a single point of failure
  Beetle handlers should automatically switch to a new redis master in case of a redis master failure
  
  Background:
    Given a redis server "redis-1" exists as master
    And a redis server "redis-2" exists as slave of "redis-1"
  
  @current  
  Scenario: Redis master switch
    Given a redis configuration server process "rc-server" exists
    And a redis configuration client process "rc-client-1" exists
    And a redis configuration client process "rc-client-2" exists
    And redis server "redis-1" is down
    And the retry timeout for the redis master check is reached
    Then the role of redis server "redis-2" should be "master"
    And the redis master of "rc-client-1" should be "redis-2"
    And the redis master of "rc-client-2" should be "redis-2"
    
  Scenario: Redis master only temporarily down (no switch necessary)
    Given a redis configuration server process "rc-server" exists
    And a redis configuration client process "rc-client-1" exists
    And a redis configuration client process "rc-client-2" exists
    And redis server "redis-1" is down for less seconds than the retry timeout for the redis master check
    And the retry timeout for the redis master check is reached
    Then the role of redis server "redis-1" should still be "master"
    Then the role of redis server "redis-2" should still be "slave"
    And the redis master of "rc-client-1" should still be "redis-1"
    And the redis master of "rc-client-2" should still be "redis-1"

  Scenario: "invalidated" message not acknowledged by all rc-clients (no switch possible)
    Given a redis configuration client process "rc-client-1" exists
    And a redis configuration client process "rc-client-2" exists
    And the redis configuration client process "rc-client-2" is disconnected from the system queue
    And redis server "redis-1" is down
    And the retry timeout for the redis master check is reached
    Then the role of redis server "redis-1" should still be "master"
    Then the role of redis server "redis-2" should still be "slave"
    And the redis master of "rc-client-1" should still be "redis-1"
    And the redis master of "rc-client-2" should still be "redis-1"
    
  Scenario: Reconfiguration round in progress
    Given a reconfiguration round is in progress
    And a redis configuration client process "rc-client-1" exists
    Then the redis master of "rc-client-1" should be nil

  Scenario: Redis master cannot be determined
    Given redis "redis-1" is down
    And redis "redis-2" is down
    And a redis configuration client process "rc-client-1" exists
    And the retry timeout for the redis master determination is reached
    Then the redis master of "rc-client-1" should be nil

  Scenario: Former redis master coming back
  