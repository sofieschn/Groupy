% group membership service 1
-module(gms1).
-export([leader/4, broadcast/3, slave/5, start/1, init/2, start/2, init/3]).

%%%%% LEADER NODE START AND INIT %%%%%

%%% Starting the first node (leader) 
%%% Starting the first node (leader) %%%
start(Id) ->
    Self = self(),
    {ok, spawn_link(fun() -> init(Id, Self) end)}.

%%% Initialization for the first node %%%
init(Id, Master) ->
    % The first node automatically becomes the leader
    leader(Id, Master, [], [Master]).


%%%%% JOINING NODE START AND INIT %%%%%

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
            % Start the slave process with the received leader, slaves, and group
            slave(Id, Master, Leader, NewSlavesList, NewGroup)
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

% Base case, end of slaves list
broadcast(_Id, _Message, []) ->
    ok;
% Recursive case, broadcasting to each slave
broadcast(Id, Message, [Slave|Rest]) ->
    io:format("Broadcasting message ~p to slave ~p~n", [Message, Slave]),  % Log broadcast messages
    Slave ! Message,
    % keep calling broadcast with the rest of the list
    broadcast(Id, Message, Rest).


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

        % Handle the stop signal (terminates the slave process)
        stop ->
            ok
    end.


