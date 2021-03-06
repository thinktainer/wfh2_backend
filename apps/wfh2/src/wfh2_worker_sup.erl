-module(wfh2_worker_sup).

-behaviour(supervisor).

%% API functions
-export([start_link/0
         , get_worker_ids/0
         , create_worker/1
         , worker_exists/1]).

%% Supervisor callbacks
-export([init/1]).

-define(WORKERS_DIRECTORY, wfh2_config:get_env(workers_directory)).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates a worker to process wfh commands
%%
%% @spec create_worker(WorkerId) -> startchild_ret()
%%
%% @end
%%--------------------------------------------------------------------

get_worker_ids() ->
  WorkerIds = lists:map(fun (Child) -> {Id, _, _, _} = Child, Id end, supervisor:which_children(?MODULE)),
  WorkerIds.

worker_exists(WorkerId) ->
  Workers = supervisor:which_children(?MODULE),
  lists:keysearch(WorkerId, 1, Workers) =/= false.

create_worker(WorkerId) ->
  Id =
    if is_list(WorkerId) -> list_to_atom(WorkerId);
       true -> WorkerId
    end,
  ChildSpec = #{  id => Id
                , start => {wfh2_worker, start_link, [Id]}
                , restart => permanent
                , shutdown => 5000
                , type => worker
                , modules => [wfh2_worker]},

  supervisor:start_child(?MODULE, ChildSpec).

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
  {ok, Workers} = load_workers(),
  supervisor:start_link({local, ?MODULE}, ?MODULE, Workers).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @end
%%--------------------------------------------------------------------
init(Workers) ->
  Children = get_children(Workers),
  {ok, {{one_for_one, 5, 10}, Children }}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
get_children(Workers) ->
  lists:map(fun create_child/1, Workers).

create_child(Name) ->
  Id = list_to_atom(Name),
  #{ id =>  Id
     , start =>  {wfh2_worker, start_link, [Id]}
     , restart => permanent
     , shutdown => 5000
     , type => worker
     , modules => [wfh2_worker]}.

load_workers() ->
  Emails = sprof_cache:get_emails(),
  {ok,  Emails}.

