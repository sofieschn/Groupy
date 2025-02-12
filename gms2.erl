% group membership service 2
-module(gms2).
-export([leader/4, broadcast/3, slave/5, start/1, init_leader/3, start/2, init/3, crash/1]).
- define(arghh, 100).

%%%%% LEADER NODE START AND INIT %%%%%

%%% Starting the first node (leader) %%%
start(Id) ->
    Rnd = rand:uniform(1000),
    Self = self(),
    {ok, spawn_link(fun() -> init(Id, Rnd, Self) end)}.

%%% Initialization for the first node %%%
init_leader(Id, Rnd, Master) ->
    rand:seed(Rnd, Rnd, Rnd),
    % The first node automatically becomes the leader
    leader(Id, Master, [], [Master]).


%%%%% JOINING NODE  - START AND INIT %%%%%

%%% Starting a node that joins an existing group (slave) %%%
start(Id, Grp) ->
    %%Self = self(),
    % Spawn a new application layer (Master) process for each joining node
    Master = spawn(fun() -> application_process() end),
    {ok, spawn_link(fun() -> init(Id, Grp, Master) end)}.

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
    
    % Send a join request to any existing node in the group
    Grp ! {join, Master, Self},
    % Wait for the view message from the leader
    receive
        {view, [Leader | NewSlavesList], NewGroup} ->
            io:format("Slave ~p received new view: Leader: ~p, Slaves: ~p, Group: ~p~n",[Id, Leader, NewSlavesList, NewGroup]),  % Print new group view
            % Inform the application layer of the updated view
            Master ! {view, NewGroup},
            %% The only node that will be monitored is the leader
			erlang:monitor(process, Leader),
            % Start the slave process with the received leader, slaves, and group
            slave(Id, Master, Leader, NewSlavesList, NewGroup)

    % create a timeout if there is no connection to the leader. To not leave it waiting forever.
	after 5000 -> 
		%% send an error message to the master when a reply is not received
        io:format("Node ~p did not receive a reply from the leader in time. Aborting join request.~n", [Id]),
		Master ! {error, "no reply from leader"}
	end.

leader(Id, Master, Slaves, Group) ->
    receive
        % sending message to entire group
        {mcast, Message} ->
            % broadcast message to all slaves. 
            % message is wrapped in a tuple to tag it with 'msg' as a label to help differentiate message from other messages such as add etc. 
            broadcast(Id, {msg, Message}, Slaves),
            % Send message to leaders own application process (Master)
            Master ! Message,
            % recursively call leader function with updated state
            leader(Id, Master, Slaves, Group);

        % new node join handler
        {join, NewWork, NewSlave} ->
            % Add the new slave to the list of slaves (end of list)
            NewSlavesList = lists:append(Slaves, [NewSlave]),
            % Add the new application process to Group 
            NewGroup = lists:append(Group, [NewWork]),
            % broadcast the new slave of the group to the slaves, the leader includes itself in the new list of slaves too
            broadcast(Id, {view, [self()| NewSlavesList], NewGroup}, NewSlavesList),
            % update its own view by "broadcasting" to itself aswell
            Master ! {view, NewGroup},
            % recursively call the leader function to keep waiting for new updates
            leader(Id, Master, NewSlavesList, NewGroup);
        stop ->
            ok

    end. 



slave(Id, Master, Leader, Slaves, Group) ->

    receive
        % Handle multicast message from the application layer or another node
        {mcast, Message} ->
            io:format("Slave ~p forwarding multicast message to leader~n", [Id]),  % Log when forwarding multicast
            % Forward the multicast message to the Leader
            Leader ! {mcast, Message},
            % Continue the slave loop with the same state
            slave(Id, Master, Leader, Slaves, Group);

        % Handle a join request for a new node
        {join, Work, Peer} ->
            io:format("Slave ~p forwarding join request to leader~n", [Id]),  % Log when forwarding join request
            % Forward the join request to the Leader
            Leader ! {join, Work, Peer},
            % Continue the slave loop with the same state
            slave(Id, Master, Leader, Slaves, Group);

        % Handle a regular message (from the leader)
        {msg, Message} ->
            io:format("Slave ~p received message from leader: ~p~n", [Id, Message]),  % Log when receiving message from leader
            % Forward the message to the application layer (Master)
            Master ! Message,
            % Continue the slave loop with the same state
            slave(Id, Master, Leader, Slaves, Group);

        % Handle a new view update (when group membership changes)
        {view, [Leader|NewSlavesList], NewGroup} ->
            io:format("Slave ~p received new view: Leader: ~p, Slaves: ~p, Group: ~p~n",[Id, Leader, NewSlavesList, NewGroup]),  % Log new group view
            % Send the new view of the group to the application layer (Master)
            Master ! {view, NewGroup},
            % Update the slave's local state with the new Leader, Slaves list, and Group
            slave(Id, Master, Leader, NewSlavesList, NewGroup);

        {'DOWN', _Ref, process, Leader, _Reason} ->
                election(Id, Master, Slaves, Group);

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


%% in the case the slaves list is empty, there can be no new elected leader
election(_Id, Master, [], _Group) ->
    io:format("No slaves left to elect a new leader. System in an isolated state.~n"),
    Master ! {error, "no slaves left for election"},
    ok;
%% elects a new leader when the leader node has 'gone down'
election(Id, Master, Slaves, [_|Group]) ->
    Self = self(),  % Get the PID of the current process
    case Slaves of
         % If the current node (Self) is the first in the Slaves list, it becomes the new leader
        [Self|Rest] ->
            broadcast(Id, {view, Slaves, Group}, Rest),  % Broadcast the new view to the other slaves
            Master ! {view, Group},  % Inform the application layer (Master) about the new view
            leader(Id, Master, Rest, Group);  % Transition the current node to the leader role

        % If the current node is not first in the Slaves list, monitor the new leader
        [Leader|Rest] ->
            erlang:monitor(process, Leader),  % Start monitoring the new leader
            slave(Id, Master, Leader, Rest, Group)  % Continue running as a slave with the new leader
    end.



