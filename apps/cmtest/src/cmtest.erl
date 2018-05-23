-module(cmtest).
-export([run/0, run/1, run/2, clear/0]).

run() -> 
    cmtest_runner:run(cmconfig:tests()).

run(Test) ->
    case cmconfig:test(Test) of
        {ok, Spec} -> 
            cmtest_runner:run(Spec);
        Other -> Other
    end.

run(Test, Scenario) ->
    case cmconfig:test(Test) of
        {ok, #{ scenarios := Scenarios }=Spec} ->
            {ok, SSpecs} = cmtest_util:scenarios(Scenario, Scenarios),
            cmtest_runner:run(Spec, SSpecs);
        Other -> Other
    end.

clear() ->
    cmtest_runner:stop().