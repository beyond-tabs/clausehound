:- module(matching_ranking, [
    named_entity/5,
    match_entity/6, 
    match_and_rank_text/3, 
    load_named_entities/0, 
    insert_named_entities_from_rows/1, 
    matches_to_json/2, 
    start_server/0
]).

:- use_module(library(odbc)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/json)).

:- debug(prolog_matcher).

% --- HTTP Server ---

:- http_handler(root(match), handle_match, []).

wait_for_exit :-
    repeat,
    sleep(3600).

start_server :-
    load_named_entities,
    http_server(http_dispatch, [port(8081)]),
    wait_for_exit.

handle_match(Request) :-
    http_read_json_dict(Request, Dict),
    Text = Dict.get(text, ""),
    match_and_rank_text(Text, Matches, _),
    reply_json_dict(_{matches: Matches}).

log(Label, Value) :-
    debug(prolog_matcher, "~w = ~w~n", [Label, Value]).

% --- Stopwords & Symbol Replacements ---

stopword("a").
stopword("an").
stopword("the").
stopword("and").
stopword("or").

symbol_replace('&', 'and').
symbol_replace('@', 'at').
symbol_replace('+', 'plus').
symbol_replace('#', 'sharp').
symbol_replace('/', 'slash').
symbol_replace('-', 'dash').

% --- Normalization ---

normalize_token(Raw, Normalized) :-
    atom_string(Raw, S),
    string_lower(S, Lower),
    ( symbol_replace(Lower, R) -> Final = R ; Final = Lower ),
    atom_string(Normalized, Final).

normalize_text(Text, NormalizedTokens) :-
    split_string(Text, " ", " ", RawTokens),
    maplist(normalize_token, RawTokens, NormalizedTokens).

% --- Entity Loading ---

:- dynamic named_entity/5.

insert_named_entities_from_rows(Rows) :-
    retractall(named_entity(_,_,_,_,_)),
    forall(member(row(Id, Name, Type, Weight, KeywordsAtom), Rows), (
        atom_json_term(KeywordsAtom, KeywordsRaw, []),
        maplist(string_lower, KeywordsRaw, LowercaseStrings),
        maplist(atom_string, LowercaseAtoms, LowercaseStrings),
        assertz(named_entity(Id, Name, Type, LowercaseAtoms, Weight))
    )).

load_named_entities :-
    ( getenv('ODBC_DSN', Dsn) -> true ; Dsn = 'MySQL_DSN' ),
    ( getenv('ODBC_USER', User) -> true ; User = 'root' ),
    ( getenv('ODBC_PASS', Pass) -> true ; Pass = 'root' ),
    ( getenv('ODBC_DB', Db) -> true ; Db = 'mydb' ),
    odbc_connect(Dsn, _Conn,
        [ user(User), password(Pass), alias(Db), open(once) ]),

    findall(row(Id, Name, Type, Weight, KeywordsAtom),
        odbc_query(mydb,
            "SELECT ne.id, ne.name, net.name AS named_entity_type_name, ne.weight, ne.keywords FROM named_entities ne INNER JOIN named_entity_types net ON ne.named_entity_type_id = net.id WHERE ne.name = 'avionics'",
            row(Id, Name, Type, Weight, KeywordsAtom)
        ),
        Rows),
    insert_named_entities_from_rows(Rows).

% --- Matching Logic ---

match_entity(EntityId, Name, Type, Keywords, Tokens, Match) :-
    named_entity(EntityId, Name, Type, Keywords, Weight),
    sublist_with_offsets(Keywords, Tokens, Start, End),
    length(Keywords, KLen),
    type_multiplier(Type, Multiplier),
    AdjustedWeight is Weight * Multiplier,
    slice_context(Tokens, Start, KLen, 3, ContextBefore, Matched, ContextAfter),
    Match = match{
        id: EntityId,
        name: Name,
        type: Type,
        weight: AdjustedWeight,
        original_weight: AdjustedWeight,
        start: Start,
        end: End,
        matched: Matched,
        context_before: ContextBefore,
        context_after: ContextAfter,
        boosted_by: []
    }.

list_starts_with([], _).
list_starts_with([X|XS], [X|YS]) :- list_starts_with(XS, YS).

sublist_with_index(Sub, List, Index, Index) :-
    list_starts_with(Sub, List), !.

sublist_with_index(Sub, [_|Tail], CurrIndex, Index) :-
    NextIndex is CurrIndex + 1,
    sublist_with_index(Sub, Tail, NextIndex, Index).

sublist_with_offsets(Sub, List, Start, End) :-
    length(Sub, Len),
    sublist_with_index(Sub, List, 0, Start),
    End is Start + Len - 1.

% --- Context Slicing ---

take_last_n(List, N, Tail) :-
    length(List, L),
    Drop is max(0, L - N),
    length(Prefix, Drop),
    append(Prefix, Tail, List).

take_first_n(List, N, Front) :-
    length(Front, N),
    append(Front, _, List), !.
take_first_n(List, _, List).

slice_context(Tokens, Start, Len, ContextSize, Before, Matched, After) :-
    length(Prefix, Start),
    append(Prefix, Rest, Tokens),
    length(Matched, Len),
    append(Matched, RestAfter, Rest),
    reverse(Prefix, RevPrefix),
    take_last_n(RevPrefix, ContextSize, RevBefore),
    reverse(RevBefore, Before),
    take_first_n(RestAfter, ContextSize, After).

% --- Type Multipliers & Boosting ---

:- dynamic type_multiplier/2.

type_multiplier("JOB_TITLE", 1.0).
type_multiplier("PROGRAMMING_LANGUAGE", 1.5).
type_multiplier("FRAMEWORK", 1.2).
type_multiplier(_, 1.0).

:- dynamic boost_rule/5.

apply_boosts(MatchesIn, MatchesOut) :-
    maplist({}/[M, Id-M] >> get_dict(id, M, Id), MatchesIn, Pairs),
    dict_create(IdMap, _, Pairs),
    maplist(apply_boost_to_match(IdMap), MatchesIn, MatchesOut).

apply_boost_to_match(IdMap, MatchIn, MatchOut) :-
    MatchIn.get(id) = TargetId,
    MatchIn.get(original_weight) = BaseWeight,
    findall(Boost, (
        boost_rule(TriggerId, TriggerName, TargetId, Strategy, BoostValue),
        get_dict(TriggerId, IdMap, _),
        apply_boost_value(BaseWeight, Strategy, BoostValue, NewWeight),
        Delta is NewWeight - BaseWeight,
        Boost = _{
            trigger_id: TriggerId,
            trigger_name: TriggerName,
            strategy: Strategy,
            value: BoostValue,
            delta: Delta
        }
    ), Boosts),
    sum_boost_deltas(Boosts, TotalDelta),
    NewWeight is BaseWeight + TotalDelta,
    MatchOut = MatchIn.put(_{weight: NewWeight, boosted_by: Boosts}).

apply_boost_value(Base, additive, Boost, New) :- New is Base + Boost.
apply_boost_value(Base, multiplicative, Boost, New) :- New is Base * Boost.
apply_boost_value(_, override, Boost, Boost).
apply_boost_value(Base, _, _, Base).

sum_boost_deltas([], 0).
sum_boost_deltas(Boosts, Total) :-
    maplist({}/[B,D]>>(D = B.delta), Boosts, Deltas),
    sum_list(Deltas, Total).

% --- Ranking ---

match_and_rank_text(Text, CleanMatches, Score) :-
    normalize_text(Text, Tokens),
    log(tokens, Tokens),
    findall(Match, match_entity(_,_,_,_,Tokens,Match), RawMatches),
    log(raw_matches, RawMatches),
    sort_matches(RawMatches, SortedRaw),
    apply_boosts(SortedRaw, Boosted),
    sort_matches(Boosted, SortedBoosted),
    sum_weights(SortedBoosted, Score),
    matches_to_json(SortedBoosted, CleanMatches).

sort_matches(Matches, Sorted) :-
    predsort(compare_by_weight, Matches, Sorted).

compare_by_weight(Delta, A, B) :-
    WA = A.weight,
    WB = B.weight,
    compare(Delta, WB, WA).

sum_weights([], 0).
sum_weights([M|T], Score) :-
    sum_weights(T, Rest),
    Score is M.weight + Rest.

% --- JSON Output Cleanup ---

strip_tag(DictWithTag, DictWithoutTag) :-
    dict_pairs(DictWithTag, _, Pairs),
    dict_create(DictWithoutTag, _, Pairs).

matches_to_json(Matches, JsonMatches) :-
    maplist(strip_tag, Matches, JsonMatches).
