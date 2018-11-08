-module(cmcore_context).
-behaviour(gen_statem).
-export([
         start_link/3,
         init/1, 
         callback_mode/0, 
         terminate/3,
         initializing/3,
         ready/3
        ]).

callback_mode() ->
    state_functions.

start_link(Spec, #{id := Id}=Session, Conn) ->
    gen_statem:start_link({global, Id}, ?MODULE, [Spec, Session, Conn], []).

init([#{ config := Config,
         debug := Debug,
         spec := Spec } = AppSpec, Session, Conn]) ->
    Timeout = maps:get(timeout, AppSpec, 10000),
    {ok, initializing, Session#{ start => cmkit:micros(),
                                 debug => Debug,
                                 timeout => Timeout,
                                 spec => Spec, 
                                 config => Config,
                                 conns => [Conn]}}.

initializing({call, From}, init,  #{app := App,
                                    config := Config0,
                                    debug := Debug,
                                    timeout := Timeout, 
                                    id := Id,
                                    spec := Spec}=Session) ->
    
    Log = cmkit:log_fun(Debug),
    Effects = cmconfig:effects(),
    {ok, Effect} = cmcore_effect_sup:start_effect(Id),
    Config = case maps:get(encoders, Spec, undef) of 
                  undef -> Config0;
                  Encs -> Config0#{ encoders => Encs }
              end,
    case cmcore_util:init(Spec, Config) of 
        {ok, Model, Cmds} -> 
            cmcore_util:cmds(Cmds, Model, Config, Session),
            {next_state, ready, Session#{ 
                                  config => Config,
                                  log => Log,
                                  effect => Effect,
                                  effects => Effects,
                                  model => Model }, [{reply, From, ok},
                                                     {state_timeout, Timeout, terminate}]};
        {error, E} -> 
            server_error(App, Session, init, E),
            {stop_and_reply, normal, reply(From, error)}
    end.

ready(cast, {update, Data}, #{ app := App, 
                               spec := Spec, 
                               config := Config,
                               model := Model,
                               log := Log
                             }=Session) ->
    
    Log({App, in, Data}),
    case cmcore_util:decode(Spec, Data, Config) of 
        {ok, Msg, Decoded} ->
            Log({App, decoded, Msg}),
            update(Spec, Msg, Decoded, Model, Config, Session);
        {error, no_match} ->
            cmkit:warning({App, no_match, Data}),
            update(Spec, no_match, Data, Model, Config, Session);
        {error, E} -> 
            server_error(App, Session, update, #{ data => Data, reason => E}),
            {keep_state, Session}

    end;

ready(cast, terminate, #{ app := App, id := Id, log := Log, effect := Effect }) ->
    Log({App, self(), Id, terminating}),
    ok = cmcore_effect:stop(Effect),
    {stop, normal};

ready(state_timeout, terminate, #{ app := App, id := Id, effect := Effect }) ->
    cmkit:warning({App, self(), Id, timeout }),
    ok = cmcore_effect:stop(Effect),
    {stop, normal};


ready({call, From}, connections,  #{conns := Conns}=Data) ->
    {keep_state, Data, reply(From, Conns)}.




update(Spec, Msg, Decoded, Model, Config, #{ app := App,
                                             spec := Spec,
                                             config := Config,
                                             model := Model
                                           }=Session) ->
    case cmcore_util:update_spec(Spec, Msg, Decoded, Model, Config) of 
        {ok, UpdateSpec} ->
            case cmcore_util:update(Spec, UpdateSpec, Config, Decoded, {Model, []}) of
                {ok, Model2, Cmds } ->
                    cmcore_util:cmds(Cmds, Model2, Config, Session),
                    {keep_state, Session#{ model => Model2 }};
                {error, E} ->
                    server_error(App, Session, update, E),
                    {keep_state, Session}
            end;
        {error, E} ->
            server_error(App, Session, update, E),
            {keep_state, Session}
    end.

server_error(App, _Session, Phase, Reason) ->
    Info = #{ status => error,
              app => App,
              phase => Phase,
              reason => Reason },
    cmkit:danger({cmcore, server_error, Info}),
    %cmcore_util:apply_effect(notify, Info, Session),
    gen_statem:cast(self(), terminate),
    Info.

terminate(_, _, #{ start := Start, app := App, id := Id, log := Log})->
    Log({App, self(), Id, terminated, cmkit:elapsed(Start)}),
    ok.

reply(From, Msg) -> [{reply, From, Msg}].
