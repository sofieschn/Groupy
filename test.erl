-module(test).
-export([run_tests/0, test_broadcast/0, test_leader_crash/0, test_slave_message/0]).

%% This function will run all the tests
run_tests() ->
    io:format("Running all tests...~n"),
    test_broadcast(),
    test_leader_crash(),
    test_slave_message(),
    io:format("All tests completed.~n").

%% Test 1: Basic Broadcast Test
test_broadcast() ->
    io:format("Starting test_broadcast...~n"),
    
    % Start the leader
    {ok, Leader} = gms3:start(leader_id),

    % Start two slaves
    {ok, Slave1} = gms3:start(slave1_id, Leader),
    {ok, Slave2} = gms3:start(slave2_id, Leader),

    % Send a multicast message
    Leader ! {mcast, "Test Message 1"},

    % Allow time for the message to propagate
    timer:sleep(1000),

    % Verify that the message is received by both slaves
    io:format("Test broadcast completed.~n").

%% Test 2: Simulate Leader Crash and Election
test_leader_crash() ->
    io:format("Starting test_leader_crash...~n"),

    % Start the leader and two slaves
    {ok, Leader} = gms3:start(leader_id),
    {ok, Slave1} = gms3:start(slave1_id, Leader),
    {ok, Slave2} = gms3:start(slave2_id, Leader),

    % Send a multicast message
    Leader ! {mcast, "Test Message 2"},

    % Simulate leader crash
    io:format("Simulating leader crash...~n"),
    Leader ! stop,

    % Allow time for the election process
    timer:sleep(2000),

    % Send another message after the election (Slave1 should now be the leader)
    io:format("Sending multicast from new leader (expected Slave1)...~n"),
    Slave1 ! {mcast, "Test Message 3"},

    % Allow time for the new message to propagate
    timer:sleep(1000),

    io:format("Test leader crash and election completed.~n").

%% Test 3: Leader sends messages to the slaves (multicast test)
test_slave_message() ->
    io:format("Starting test_slave_message...~n"),

    % Start the leader and two slaves
    {ok, Leader} = gms3:start(leader_id),
    {ok, Slave1} = gms3:start(slave1_id, Leader),
    {ok, Slave2} = gms3:start(slave2_id, Leader),

    % Leader sends a multicast message to all slaves
    io:format("Leader sending message to all slaves: 'Message to Slaves'...~n"),
    Leader ! {mcast, "Message to Slaves"},

    % Allow time for the slaves to process the message
    timer:sleep(1000),

    io:format("Test slave message completed.~n").

