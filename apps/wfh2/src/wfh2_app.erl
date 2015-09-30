%%%-------------------------------------------------------------------
%% @doc wfh2 public API
%% @end
%%%-------------------------------------------------------------------

-module('wfh2_app').

-behaviour(application).

%% Application callbacks
-export([start/2
        ,stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    Dispatch =
      cowboy_router:compile([ {'_',[{"/", wfh2_handler, []}]}]),
      {ok, _} = cowboy:start_http(http, 100, [{port, 8080}], 
                                 [{env, [{dispatch, Dispatch}]}]),
    wfh2_sup:start_link().


%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
