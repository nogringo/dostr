## 0.1.0

 - Initial release, moved out of `dostr_fetchers` with `HomeRelayList`, `defaultHomeRelayListUrl` and `defaultHomeRelayListAuthor`.
 - `HomeRelayList.candidates` and `homeRelaysOf` give `RelayUrl`s, from `dostr_relay_url`.
 - `HomeRelayList.fetch` takes an optional `client`, an `http.Client` it sends the request with and leaves open. Its `timeout` covers the whole response and aborts the request, so it does not hold a socket of that client, and holds with a client that ignores the abort trigger too.
