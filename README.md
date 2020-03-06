# Find Dan Q

Where's Dan Q? You can see his real-time location at https://find.danq.me/. It'll be very inaccurate
(both "fuzzy" - having a large radius - and "drifted" - being away from the correct location) unless you've
appropriately authenticated.

## Find "You"

To set up your own:

1. Set up a [uLogger server](https://github.com/bfabiszewski/ulogger-server) and [uLogger mobile client](https://github.com/bfabiszewski/ulogger-android) to log your location to your server.
2. Get yourself a Google reverse geocoding API key (to convert locations into approximate addresses)
3. Clone this repo
4. Copy `.env.example` to `.env` and edit to your preference; if relying on drift, ensure you set the `DRIFT_SEED_SALT` to a large random number or else your location can be reverse-engineered!
5. Deploy as per any other Ruby+Sinatra application

## License

Licensed under the BSD 2-Clause "Simplified" License. See `LICENSE`.

