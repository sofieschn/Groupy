% group membership service 1
-module(gms1).
-export([leader/4, broadcast/3, slave/5, start/1, init/3]).

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
    Slave ! Message,
    % keep calling broadcast with the rest of the list
    broadcast(Id, Message, Rest).


slave(Id, Master, Leader, Slaves, Group) ->
    receive
        % Handle multicast message from the application layer or another node
        {mcast, Message} ->
            % Forward the multicast message to the Leader
            Leader ! {mcast, Message},
            % Continue the slave loop with the same state
            slave(Id, Master, Leader, Slaves, Group);

        % Handle a join request for a new node
        {join, Work, Peer} ->
            % Forward the join request to the Leader
            Leader ! {join, Work, Peer},
            % Continue the slave loop with the same state
            slave(Id, Master, Leader, Slaves, Group);

        % Handle a regular message (from the leader)
        {msg, Message} ->
            % Forward the message to the application layer (Master)
            Master ! Message,
            % Continue the slave loop with the same state
            slave(Id, Master, Leader, Slaves, Group);

        % Handle a new view update (when group membership changes)
        {view, [Leader|NewSlavesList], NewGroup} ->
            % Send the new view of the group to the application layer (Master)
            Master ! {view, NewGroup},
            % Update the slave's local state with the new Leader, Slaves list, and Group
            slave(Id, Master, Leader, NewSlavesList, NewGroup);

        % Handle the stop signal (terminates the slave process)
        stop ->
            ok
    end.



start(Id, Group) ->
    Self = self(),
    {ok, spawn_link(fun()-> init(Id, Group, Self) end)}.
init(Id, Group, Master) ->
    Self = self(),
    Group ! {join, Master, Self},
    receive
        {view, [Leader|Slaves], Group} ->
            Master ! {view, Group},
            slave(Id, Master, Leader, Slaves, Group)
end.

