%% Test 4: Rotate leadership among slaves and kill each leader until Slave4 is the final leader
-module(test2).
-export([test_leader_rotation/0]).

test_leader_rotation() ->
    io:format("Starting test_leader_rotation...~n"),

    % Step 1: Start Slave1 as the leader and add Slave2 and Slave3
    {ok, Leader1} = gms3:start(slave1_id),  % Slave1 is the initial leader
    {ok, Slave2} = gms3:start(slave2_id, Leader1),
    {ok, Slave3} = gms3:start(slave3_id, Leader1),

    timer:sleep(1000),  % Allow time for group setup

    % Step 2: Kill Slave1 (the leader) and add Slave4, Slave2 becomes the new leader
    io:format("Killing Slave1 (Leader1) and adding Slave4...~n"),
    Leader1 ! stop,  % Kill the leader (Slave1)
    timer:sleep(2000),  % Allow time for Slave2 to become leader

    % Add Slave4 (new slave) after Slave1 is killed
    {ok, Slave4} = gms3:start(slave4_id, Slave2),  % Slave2 is now the leader   
    {ok, Slave5} = gms3:start(slave5_id, Slave2),  % Slave2 is now the leader
    {ok, Slave6} = gms3:start(slave6_id, Slave2),  % Slave2 is now the leader

    timer:sleep(2000),  % Allow time for Slave4,5,6 to join the group

    % Step 3: Kill Slave2 (the leader), Slave3 becomes the new leader
    io:format("Killing Slave2 (Leader2)...~n"),
    Slave2 ! stop,  % Kill the new leader (Slave2)
    timer:sleep(2000),  % Allow time for Slave3 to become leader

    % Step 4: Kill Slave3 (the leader), Slave4 becomes the new leader
    io:format("Killing Slave3 (Leader3)...~n"),
    Slave3 ! stop,  % Kill the new leader (Slave3)
    timer:sleep(2000),  % Allow time for Slave4 to become leader

    io:format("Slave4 has now become the leader, and all original slaves have been killed.~n").
