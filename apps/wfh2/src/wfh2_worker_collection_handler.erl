-module(wfh2_worker_collection_handler).

-export([init/3
        , allowed_methods/2
        , content_types_provided/2
        , content_types_accepted/2
        , resource_exists/2
        , get_json/2
        , post_json/2]).

init(_Proto, _Req, _Opts) ->
  {upgrade, protocol, cowboy_rest}.

allowed_methods(Req, State) ->
  {[<<"GET">>, <<"POST">>], Req, State}.

content_types_provided(Req, State) ->
  {[{{<<"application">>, <<"json">>, []}, get_json}], Req, State}.

content_types_accepted(Req, State) ->
  {[{{<<"application">>, <<"json">>, []}, post_json}], Req, State}.

resource_exists(Req, State) ->
  case cowboy_req:method(Req) of
    {<<"GET">>, Req2} -> {true, Req2, State};
    {<<"POST">>, Req2} ->
      {ok, BodyRaw, Req3} = cowboy_req:body(Req2),
      #{id := IdRaw, name := Name} = jsx:decode(BodyRaw, [return_maps, {labels, atom}]),
      Id = binary_to_atom(IdRaw, utf8),
      Exists = wfh2_worker_sup:worker_exists(Id),
      State2 = #{id => Id, name => binary_to_list(Name)},
      {Exists, Req3, State2}
  end.

get_json(Req, State) ->
  WorkerIds = wfh2_worker_sup:get_worker_ids(),
  WorkerStates =
  lists:map(fun (Wid) ->
                {ok, WorkerState} =
                wfh2_worker:get_worker_state(Wid),
                WorkerState
            end, WorkerIds),

  WorkerPresentations =
  lists:foldl(fun (Ele, Acc) ->
                  EncEle = wfh2_serialisation:encode_status(Ele),
                  case Acc =:= <<>> of
                    true ->
                      EncEle;
                    _ ->
                      <<Acc/binary, $,, EncEle/binary>>
                  end
              end, <<>>, WorkerStates),

  Body = <<"[", WorkerPresentations/binary, "]">>,
  {Body, Req, State}.

post_json(Req, State) ->
  error_logger:info_msg(
    "collection_handler:post_json handling message"),
  #{id := Id, name := Name} = State,
  BinId = atom_to_binary(Id, utf8),
  case wfh2_worker:create_worker(Id, Name) of
    ok ->
      {{true, <<"/workers/", BinId/binary>>}, Req, State};
    {error, worker_exists} ->
      {{true, <<"/workers/", BinId/binary>>}, Req, State}
  end.
