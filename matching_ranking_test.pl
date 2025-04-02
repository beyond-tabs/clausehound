:- use_module(matching_ranking).

:- begin_tests(matcher).


test(insert_mock_entity) :-
    FakeData = [
        row('1', 'Avionics', 'Category', 1.0, '["avionics","airplane systems"]')
    ],
    insert_named_entities_from_rows(FakeData),
    named_entity('1', 'Avionics', 'Category', Keywords, 1.0),
    assertion(Keywords == [avionics, 'airplane systems']).


test(match_basic_entity) :-
    assertz(named_entity('ent-1', 'Avionics', 'Category', [avionics], 1.0)),

    Tokens = [the, avionics, systems, are, complex],

    match_entity('ent-1', _, _, [avionics], Tokens, Match),

    assertion(Match.name == 'Avionics'),
    assertion(Match.type == 'Category'),
    assertion(Match.weight == 1.0),
    assertion(Match.start == 1),
    assertion(Match.end == 1),
    assertion(Match.context_before == [the]),
    assertion(Match.context_after == [systems, are, complex]),

    retractall(named_entity(_,_,_,_,_)).


test(no_match_found, [fail]) :-
    assertz(named_entity('ent-2', 'Rocket', 'Category', [rocket], 1.0)),
    Tokens = [bananas, are, tasty],
    match_entity('ent-2', _, _, [rocket], Tokens, _).
    

:- end_tests(matcher).

