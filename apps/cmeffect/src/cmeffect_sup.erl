-module(cmeffect_sup).
-behaviour(supervisor).
-export([start_link/0]).
-export([init/1]).
-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    {ok, { {one_for_all, 0, 1}, [ 
                                 effect_spec(Effect) || Effect <- cmconfig:effects() 
                                ]}}.

effect_spec(#{ name := Name }=Effect) ->
    cmkit:child_spec(Name, cmeffect_server, [Effect], worker).