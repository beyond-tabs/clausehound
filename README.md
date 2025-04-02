# Clausehound

Clausehound is a lightweight Prolog-based matching and ranking engine for named entities in natural language text.

It tokenizes input text, applies exact and fuzzy pattern matching against known entities, ranks matches by weighted scores, and supports rule-based boosting.

This is based on a PHP service which at the moment is substantially more capable than this Prolog port. I shall try to add the remaining features in due course. At the moment though, this is to be treated as an experiment, also considering that it wouldn't have been possible without the help of LLMs.

## Requirements

- SWI-Prolog 9.x or later
- `sudo apt install swi-prolog-odbc`
- MySQL ODBC connector (`libmyodbc`)
- `unixodbc` package installed

## Running

1. Clone the repository.

2. Edit your database connection in `load_named_entities/0` to match your MySQL setup.

3. Start the server:

   ```bash
   swipl
   ?- [matching_ranking].
   ?- start_server.
   ```

4. Send a POST request:

   ```
   POST http://localhost:8081/match
   Content-Type: application/json

   {
     "text": "avionics"
   }
   ```

   ```
   {
    "matches": [
        {
        "boosted_by": [],
        "context_after": [],
        "context_before": [],
        "end":0,
        "id":"<uuid>",
        "matched": ["avionics" ],
        "name":"avionics",
        "original_weight":10.0,
        "start":0,
        "type":"QUALIFIER",
        "weight":10.0
        }
    ]
    }
   ```

### Running with Docker

`docker-compose up --build`

#### Known issues with Docker

The very first time you run `docker-compose`, MySQL will load the schema file, resulting in the Prolog application to run too soon - a restart fixes it. If you know how to fix it... I'd appreciate enormously a PR!

## License

MIT
