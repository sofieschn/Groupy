% group membership service 2
-module(gms3).
-export([leader/5, broadcast/3, slave/7, start/1, init_leader/3, start/2, init/3, crash/1]).
- define(arghh, 1000).
- define(timeout, 2000).

%%%%% LEADER NODE START AND INIT %%%%%

%%% Starting the first node (leader) %%%
start(Id) ->
    Rnd = rand:uniform(1000),
    Self = self(),
    {ok, spawn_link(fun() -> init_leader(Id, Rnd, Self) end)}.

%%% Initialization for the first node %%%
init_leader(Id, Rnd, Master) ->
    rand:seed(exsplus, {Rnd, Rnd, Rnd}),
    % The first node automatically becomes the leader
    leader(Id, Master, 0, [], [Master]).


%%%%% JOINING NODE  - START AND INIT %%%%%

%%% Starting a node that joins an existing group (slave) %%%
start(Id, Group) ->
    %%Self = self(),
    % Spawn a new application layer (Master) process for each joining node
    Master = spawn(fun() -> application_process() end),
    {ok, spawn_link(fun() -> init(Id, Group, Master) end)}.

%% starts an application process for each started node. They all get unique processIDs
application_process() ->
    receive
        % Handle messages from the group process
        Message ->
            application_process()
    end.

%%% Initialization for a joining node %%%
init(Id, Grp, Master) ->
	Self = self(),

	%% We need to send a {join, Master, self()} message to a node in the group and wait for an invitation.
	Grp ! {join, Master, Self},
	receive
		%% The invitation is delivered as a view message containing everything we need to know.
		{view, N, [Leader|Slaves], Group} ->
			Master ! {view, Group},

			%% The only node that will be monitored is the leader
			erlang:monitor(process, Leader),

			%% This process will be a slave
			%% {view, [Leader|Slaves], Group} is the last message received, so we call slave with this message
			slave(Id, Master, Leader, N+1, {view, N, [Leader|Slaves], Group}, Slaves, Group)

	%% Since the leader can crash it could be that a node that wants to join the group will never receive a reply.
	%% Therefore, we only wait a certain amount of time for a reponse
	after ?timeout ->
		%% send an error message to the master when a reply is not received
		Master ! {error, "no reply from leader"}
	end.


leader(Id, Master, MessageNumber, Slaves, Group) ->
    receive
        % sending message to entire group
        {mcast, Message} ->
            % broadcast message to all slaves. 
            % message is wrapped in a tuple to tag it with 'msg' as a label to help differentiate message from other messages such as add etc. 
            broadcast(Id, {msg, MessageNumber, Message}, Slaves),
            % Send message to leaders own application process (Master)
            Master ! Message,
            % recursively call leader function with updated state, increment messagenumber for each time
            leader(Id, Master, MessageNumber+1, Slaves, Group);

        % new node join handler
        {join, NewWork, NewSlave} ->
            % Add the new slave to the list of slaves (end of list)
            NewSlavesList = lists:append(Slaves, [NewSlave]),
            % Add the new application process to Group 
            NewGroup = lists:append(Group, [NewWork]),
            % broadcast the new slave of the group to the slaves, the leader includes itself in the new list of slaves too
            broadcast(Id, {view, MessageNumber, [self()| NewSlavesList], NewGroup}, NewSlavesList),
            % update its own view by "broadcasting" to itself aswell
            Master ! {view, NewGroup},
            % recursively call the leader function to keep waiting for new updates
            leader(Id, Master, MessageNumber+1, NewSlavesList, NewGroup);
        stop ->
            io:format("Leader ~p is stopping~n", [Id]),
            exit(normal)

    end. 



slave(Id, Master, Leader, MessageNumber, LastMessage, Slaves, Group) ->

    receive
        % Handle multicast message from the application layer or another node
        {mcast, Message} ->
            io:format("Slave ~p forwarding multicast message to leader~n", [Id]),  % Log when forwarding multicast
            % Forward the multicast message to the Leader
            Leader ! {mcast, Message},
            % Continue the slave loop with the same state
            slave(Id, Master, Leader, MessageNumber, LastMessage, Slaves, Group);

        % Handle a join request for a new node
        {join, Work, Peer} ->
            io:format("Slave ~p forwarding join request to leader~n", [Id]),  % Log when forwarding join request
            % Forward the join request to the Leader
            Leader ! {join, Work, Peer},
            % Continue the slave loop with the same state
            slave(Id, Master, Leader, MessageNumber, LastMessage, Slaves, Group);

        % Handle a regular message (from the leader)
        {msg, MessageNumber, Message} ->
            io:format("Slave ~p received message from leader: ~p~n", [Id, Message]),  % Log when receiving message from leader
            % Forward the message to the application layer (Master)
            Master ! Message,
            % Continue the slave loop with the same state
            slave(Id, Master, Leader, MessageNumber+1, {msg, MessageNumber, Message}, Slaves, Group);

        %% Since this message has a lower count, it is old and can be discarded
		%% Therefor, we do not increment N nor do we add the message as last message
        % Discard duplicate or old messages (those with a lower sequence number)
        {msg, ReceivedNumber, _} when ReceivedNumber < MessageNumber ->
            slave(Id, Master, Leader, MessageNumber, LastMessage, Slaves, Group);

        % Handle a new view update (when group membership changes)
        {view, MessageNumber, [Leader|NewSlavesList], NewGroup} ->
            io:format("Slave ~p received new view: Leader: ~p, Slaves: ~p, Group: ~p~n",[Id, Leader, NewSlavesList, NewGroup]),  % Log new group view
            % Send the new view of the group to the application layer (Master)
            Master ! {view, NewGroup},
            % Update the slave's local state with the new Leader, Slaves list, and Group
            % call the slave function with the incremented messagenumber and updated last message
            slave(Id, Master, Leader, MessageNumber+1, {view, MessageNumber, [Leader|NewSlavesList], NewGroup}, Slaves, Group);

        {'DOWN', _Ref, process, Leader, _Reason} ->
            io:format("Slave ~p detected leader ~p crashed. Moving to election...~n", [Id, Leader]),
            election(Id, Master, MessageNumber, LastMessage, Slaves, Group);

        % Handle the stop signal (terminates the slave process)
        stop ->
            ok
    end.

% random crash generator
crash(Id) ->
    % each time crash process is called which should be 1/100 chance each time broadcast is called, the leader is killed
    case rand:uniform(?arghh) of
        ?arghh ->
            io:format("leader ~w: crash~n", [Id]),
            exit(no_luck);
        _ -> ok
    end.

% Base case, end of slaves list
broadcast(_Id, _Message, []) ->
    ok;
% Recursive case, broadcasting to each slave
broadcast(Id, Message, [Slave|Rest]) ->
    % simulating a crash by crashing a process by 1/100 chance
    lists:foreach(fun(Node) -> Node ! Message, crash(Id) end, [Slave|Rest]),
    io:format("Broadcasting message ~p to slave ~p~n", [Message, Slave]),  % Log broadcast messages
    Slave ! Message,
    % keep calling broadcast with the rest of the list
    broadcast(Id, Message, Rest).


%% Elects a new leader when the leader node has 'gone down'
election(Id, Master, MessageNumber, LastMessage, Slaves, Group) ->
    Self = self(),  % Get the PID of the current process
    case Slaves of
        % If the current node (Self) is the first in the Slaves list, it becomes the new leader
        [Self | Rest] ->
            io:format("Node ~p is becoming the new leader and resending the last message.~n", [Id]),

            % Send the last message of the previous leader to self (leader) to trigger resending
            Self ! LastMessage,

            % Inform the application layer (Master) about the new view
            io:format("Informing Master of the new group view: ~p~n", [Group]),
            Master ! {view, Group}, 

            % Transition the current node to the leader role
            leader(Id, Master, MessageNumber + 1, Rest, Group);

        % If the current node is not the first in the Slaves list, monitor the new leader
        [Leader | Rest] ->
            io:format("Node ~p is electing new leader: ~p~n", [Id, Leader]),

            % Start monitoring the new leader to detect crashes
            erlang:monitor(process, Leader),

            % Continue running as a slave with the new leader
            slave(Id, Master, MessageNumber, LastMessage, Leader, Rest, Group)
    end.



