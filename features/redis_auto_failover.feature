Feature: Redis auto failover
  In order to eliminate a single point of failure
  Beetle handlers should automatically switch to a new redis master in case of a redis master failure
  
  Background:
    Given a redis server "redis-1" exists as master
    And a redis server "redis-2" exists as slave of "redis-1"
    And a redis configuration server using redis servers "redis-1,redis-2" exists
  
  Scenario: Successful redis master switch
    Given a redis configuration client "rc-client-1" using redis servers "redis-1,redis-2" exists
    And a redis configuration client "rc-client-2" using redis servers "redis-1,redis-2" exists
    And a beetle handler using the redis-master file from "rc-client-1" exists
    And redis server "redis-1" is down
    And the retry timeout for the redis master check is reached
    Then the role of redis server "redis-2" should be master
    And the redis master of "rc-client-1" should be "redis-2"
    And the redis master of "rc-client-2" should be "redis-2"
    And the redis master of the beetle handler should be "redis-2"
    
  Scenario: Redis master only temporarily down (no switch necessary)
    Given a redis configuration client "rc-client-1" using redis servers "redis-1,redis-2" exists
    And a redis configuration client "rc-client-2" using redis servers "redis-1,redis-2" exists
    And a beetle handler using the redis-master file from "rc-client-1" exists
    And redis server "redis-1" is down for less seconds than the retry timeout for the redis master check
    And the retry timeout for the redis master check is reached
    Then the role of redis server "redis-1" should still be "master"
    Then the role of redis server "redis-2" should still be "slave"
    And the redis master of "rc-client-1" should still be "redis-1"
    And the redis master of "rc-client-2" should still be "redis-1"
    And the redis master of the beetle handler should be "redis-1"

  Scenario: "invalidated" message not acknowledged by all redis configuration clients (no switch possible)
    Given a redis configuration client "rc-client-1" using redis servers "redis-1,redis-2" exists
    And a redis configuration client "rc-client-2" using redis servers "redis-1,redis-2" exists
    And the redis configuration client "rc-client-2" is disconnected from the system queue
    And redis server "redis-1" is down
    And the retry timeout for the redis master check is reached
    Then the role of redis server "redis-1" should still be "master"
    Then the role of redis server "redis-2" should still be "slave"
    And the redis master of "rc-client-1" should still be "redis-1"
    And the redis master of "rc-client-2" should still be "redis-1"
    
  Scenario: Redis configuration client joins while reconfiguration round in progress
    Given a reconfiguration round is in progress
    And a redis configuration client "rc-client-1" using redis servers "redis-1,redis-2" exists
    Then the redis master of "rc-client-1" should be nil

  Scenario: Redis configuration client can not determine current redis master
    Given redis server "redis-1" is down
    And redis server "redis-2" is down
    And a redis configuration client "rc-client-1" using redis servers "redis-1,redis-2" exists
    And the retry timeout for the redis master determination is reached
    Then the redis master of "rc-client-1" should be nil

  Scenario: Former redis master coming back online

  Scenario: Clients should not use the redis while a reconfiguration is in progress
  
  Scenario: Ambiguity when determining initial redis master 
  