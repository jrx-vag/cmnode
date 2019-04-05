-module(cmevents_writer).
-behaviour(gen_server).
-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link(Bucket) ->
    gen_server:start_link(?MODULE, [Bucket], []).

init([#{ name := Name }=B]) ->
    Data = start(B),
    Topic = cmevents_util:writer(Name),
    cmbus:create_sub(Topic),
    {ok, Data}.

handle_call(reset, _, Data) ->
    {ok, Data2} = reset(Data),
    {reply, ok, Data2};

handle_call({write, Type, Id, Name, EvData}, _, #{ pid := Pid,
                                                 tree := Tree }=Data) ->
    case write_entries(Pid, Tree, [{{Type, Id, Name}, EvData}]) of
        {ok, Tree2} ->
            {reply, ok, Data#{ tree => Tree2}};
        Other ->
            {reply, Other, Data}
    end;

handle_call(_, _, Data) ->
    {reply, ignored, Data}.

handle_cast(_, Data) ->
    {noreply, Data}.

handle_info(_, Data) ->
    {noreply, Data}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(Reason, Bucket) ->
    cmkit:warning({cmdb, writer, node(), Bucket, terminated, Reason}),
    ok.


write_entries(Pid, Tree, ToAdd) ->

    {ok, Tree2} = cbt_btree:add(Tree, ToAdd),
    Root = cbt_btree:get_state(Tree2),
    Header = {1, Root},
    case cbt_file:write_header(Pid, Header) of
        {ok, _} ->
            {ok, Tree2};
        {error, E} ->
            {error, E}
    end.

open(Name) ->
    Filename = filename:join([cmkit:data(), atom_to_list(Name) ++ ".cbt"]),
    {ok, Pid} = cbt_file:open(Filename, [create_if_missing]),
    R = case cbt_file:read_header(Pid) of
        {ok, _Header, _} ->
            {ok, Pid};
        no_valid_header ->
            {ok, T} = cbt_btree:open(nil, Pid),
            case write_entries(Pid, T, [{{0, 0, 0},0}]) of
                {ok, _} ->
                    {ok, Pid};
                Other ->
                    Other
            end
    end,

    case R of
        {ok, Pid} ->
            Topic = cmdb_util:reader(Name),
            cmbus:create(Topic),
            cmbus:sub(Topic, Pid),
            {ok, Pid};
        Other2 ->
            Other2
    end.

start(#{ name := Name,
         debug := Debug } = B) ->
    Log = cmkit:log_fun(Debug),
    {ok, Pid} = open(Name),
    Ref = erlang:monitor(process, Pid),
    {ok, Header, _} = cbt_file:read_header(Pid),
    {_, Root} = Header,
    {ok, Tree} = cbt_btree:open(Root, Pid),
    Log({cmevents, Name}),
    B#{ host => node(),
        tree => Tree,
        log => Log,
        pid => Pid,
        ref => Ref }.

reset(#{ log := Log,
         name := Name,
         pid := Fd,
         ref := Ref} = Data) ->
    erlang:demonitor(Ref),
    ok = cbt_file:close(Fd),
    Filename = filename:join([cmkit:data(), atom_to_list(Name) ++ ".cbt"]),
    ok = file:delete(Filename),
    Data2 = start(Data),
    Log({Name, resetted}),
    {ok, Data2}.