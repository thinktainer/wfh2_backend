-module(wfh2_todays_status).

-include("../include/worker_state.hrl").

-export([get/0
        , working_from/2
        , transform_worker_state/2]).

get() ->
  AllWorkerStates = wfh2_worker:get_worker_states(),
  AllWorkerStates.

-spec(transform_worker_state(WorkerState :: worker_state(), CurrentTimestamp ::
                            erlang:datetime()) -> term()).
transform_worker_state(WorkerState, CurrentTimestamp) ->
  LastUpdatedOrDefault = working_from(WorkerState,
                                      calendar:now_to_datetime(CurrentTimestamp)),
  #{email => atom_to_binary(WorkerState#worker_state.id, utf8)
   , working_from => LastUpdatedOrDefault }.

normalised_date({{Year, Month, Day}, {Hour, _, _}}, CutOffHour)
  when Hour > CutOffHour ->
  {Year, Month, Day + 1};
normalised_date({{Year, Month, Day}, _}, _CutOffHour) ->
  {Year, Month,Day}.

working_from(WorkerState, CurrentDateTime) ->
  LastUpdated = calendar:now_to_datetime(WorkerState#worker_state.last_updated),
  DateUpdateAppliesTo = normalised_date(LastUpdated, 19),
  DateShouldGetUpdateFor = normalised_date(CurrentDateTime, 19),
  ShouldGetCurrentUpdate =
  calendar:date_to_gregorian_days(DateShouldGetUpdateFor) =:=
  calendar:date_to_gregorian_days(DateUpdateAppliesTo),
  WorkingFrom = if ShouldGetCurrentUpdate ->
                     {todays_update, WorkerState#worker_state.working_from};
                   true -> {default, WorkerState#worker_state.default}
                end,
  WorkingFrom.

