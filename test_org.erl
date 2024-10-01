-module(test_org).

-compile(export_all).



% Used to create the first worker, try:
%
% W1 = test:first(1, gms1, 1000)

first(N, Module, Sleep) ->
   worker:start(N, Module, random:uniform(256), Sleep).
   

% Used to create additional workers, try:
%
%  test_org:add(2, gms1, W1, 1000) and 
%  test_org:add(3, gms1, W1, 1000) and ...

add(N, Module, Wrk, Sleep) ->
   worker:start(N, Module, random:uniform(256), Wrk, Sleep).

%% To create a number of workers in one go, 

more(N, Module, Sleep) when N > 1 ->
    Wrk = first(1, Module, Sleep),
    Ns = lists:seq(2,N),
    lists:map(fun(Id) -> add(Id, Module, Wrk, Sleep) end, Ns),
    Wrk.

test_stop_leader(N, Module, Sleep) ->
    io:format("Starting test to kill the leader...~n"),
    
    % Step 1: Start the leader and slaves using more/3
    Wrk = test_org:more(N, Module, Sleep),
    
    % Allow some time for initialization
    timer:sleep(100000),

    % Step 2: Simulate killing the leader (first node)
    io:format("Killing the leader (first node)...~n"),
    exit(Wrk, kill),

    % Step 3: Allow time for leader re-election
    timer:sleep(2000),

    io:format("Leader has been killed. A new leader should have been elected...~n").

		      

% These are messages that we can send to one of the workers. It will
% multicast it to all workers. They should (if everything works)
% receive the message at the same (logical) time.

freeze(Wrk) ->
    Wrk ! {send, freeze}.

go(Wrk) ->
    Wrk ! {send, go}.
    

sleep(Wrk, Sleep) ->
    Wrk ! {send, {sleep, Sleep}}.




			  

















