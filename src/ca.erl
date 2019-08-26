-module(ca).
-compile(export_all).
-behaviour(application).
-behaviour(supervisor).
-export([start/2, stop/1, init/1]).

start(_StartType, _StartArgs) ->
   R = cowboy_router:compile([{'_', [{"/", ca_enroll, []}]}]),
   {ok, _} = cowboy:start_clear(http,[{port,8046}],#{env => #{dispatch => R}}),
   supervisor:start_link({local, ?MODULE}, ?MODULE, []).
stop(_State) -> ok.
init([]) -> {ok, { {one_for_one, 5, 10}, []} }.
