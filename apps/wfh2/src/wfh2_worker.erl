-module(wfh2_worker).

-behaviour(gen_server).

%% API functions
-export([start_link/1
        , create_worker/2
        , set_wfh/2
        , set_wfo/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {
          id :: atom()
          , name = '' :: string()
          , version = 0 :: integer()
          , email = '' :: string()
          , working_from = office :: home | office
          , info = '' :: string()
          , last_updated = erlang:timestamp() :: erlang:timestamp()
          , slack_id = '' :: string()}).

-type event_type() :: name_updated | location_updated.

-record(event, {
          event_type :: event_type()
          , timestamp :: erlang:timestamp()
          , payload :: term()
         }).

-type event() :: #event{}.

-define(WORKERID_FILENAME_REGEX, "[^a-zA-Z_+@.]+").
-define(WORKERS_DIRECTORY, "/Users/martinschinz/tmp/wfh2/workers").

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Initialises a worker
%%
%% @spec create_worker(WorkerId :: atom(), Name :: string()) -> ok | {error, Error}
%% @end
%%--------------------------------------------------------------------
create_worker(WorkerId, Name) ->
  {ok, Pid} = wfh2_worker_sup:create_worker(WorkerId),
  gen_server:call(Pid, {set_name, Name}).

%%--------------------------------------------------------------------
%% @doc
%% Sets a worker to working from home
%%
%% @spec set_wfh(WorkerId :: atom() | string(), Info :: string()) -> ok | {error, Error}
%% @end
%%--------------------------------------------------------------------
set_wfh(WorkerId, Info) ->
  Id = ensure_atom(WorkerId),
  gen_server:call(Id, {set_wfh, Info}).

%%--------------------------------------------------------------------
%% @doc
%% Sets a worker to working from office
%%
%% @spec set_wfh(WorkerId :: atom() | string(), Info :: string()) -> ok | {error, Error}
%% @end
%%--------------------------------------------------------------------
set_wfo(WorkerId) ->
  Id = ensure_atom(WorkerId),
  gen_server:call(Id, {set_wfo}).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Id) ->
    gen_server:start_link({local, Id}, ?MODULE, [Id], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Id]) ->
  Email = atom_to_list(Id),
  WorkerFilePath = get_worker_file_path(?WORKERS_DIRECTORY, Email),
  case replay(WorkerFilePath, #state{}) of
    {ok, State} -> {ok, State};
    _ -> {ok, #state{ id = Id, email = atom_to_list(Id) }}
  end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------

handle_call({set_name, _}, _From, State) when State#state.version > 0 ->
  Reply = {error, "Name change not implemented"},
  { reply, Reply, State };

handle_call({set_name, Name}, _From, State) ->
  Event = #event{event_type = name_updated
                 , timestamp = erlang:timestamp()
                 , payload = Name},
  store_and_publish_event(Event, State#state.id),
  NewState = apply_event(Event, State),
  { reply, ok, NewState };

handle_call({set_wfh, _Info}, _From, State) when State#state.version < 1 ->
  Reply = {error, "Worker has not been created"},
  {reply, Reply, State};
handle_call({set_wfh, Info}, _From, State) ->
  Event = #event{  event_type = location_updated
                 , timestamp = erlang:timestamp()
                 , payload = {home, Info}},
  store_and_publish_event(Event, State#state.id),
  NewState = apply_event(Event, State),
  { reply, ok, NewState };

handle_call({set_wfo}, _From, State) when State#state.version < 1 ->
  Reply = {error, "Worker has not been created"},
  {reply, Reply, State};
handle_call({set_wfo}, _From, State) ->
  Event = #event{  event_type = location_updated
                , timestamp = erlang:timestamp()
                , payload = {office}},
  store_and_publish_event(Event, State#state.id),
  NewState = apply_event(Event, State),
  { reply, ok, NewState };

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

store_and_publish_event(Event, WorkerId) ->
  WorkerFilePath = get_worker_file_path(
                     ?WORKERS_DIRECTORY
                     , atom_to_list(WorkerId)),

  store_event(Event, WorkerFilePath),
  publish_event(Event).

store_event(Event, WorkerFilePath) ->
  {ok, Io} = file:open(WorkerFilePath, [append]),
  ok = io:fwrite(Io, "~p.~n", [Event]).

replay(WorkerFilePath, State) ->
  case file:consult(WorkerFilePath) of
    {ok, Terms} -> {ok, apply_events(Terms, State)};
    {error, Error} -> {error, Error}
  end.

apply_events(Events, State) ->
  lists:foldl(fun apply_event/2, State, Events).

-spec apply_event (Event :: event(), #state{}) -> #state{}.

apply_event(Event, State) ->
  UpdatedState =
    case Event of
      #event{event_type = location_updated
             , timestamp = Timestamp
             , payload ={Location, Info}} ->
        State#state{
          working_from = Location
          , last_updated = Timestamp
          , info = Info};
      #event{event_type = name_updated
             , timestamp = Timestamp
             , payload = Name} ->
        State#state{ name = Name , last_updated = Timestamp}
    end,
  UpdatedState#state{version = UpdatedState#state.version + 1}.

publish_event(Event) -> io:format("Publish Event: ~p~n", [Event]).

get_worker_file_path(WorkersPath, WorkerId) ->
  WorkerFilename = get_worker_filename(WorkerId),
  Path = filename:join(WorkersPath, WorkerFilename),
  string:concat(Path, ".txt").

get_worker_filename(WorkerId) ->
  re:replace(WorkerId
             , ?WORKERID_FILENAME_REGEX
             , ""
             , [global, {return, list}]).

ensure_atom(ListOrAtom) ->
  if is_list(ListOrAtom) -> list_to_atom(ListOrAtom);
          true -> ListOrAtom
  end.