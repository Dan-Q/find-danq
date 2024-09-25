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

## Sample Nginx conf (probably not clever, but this worked on one server for about 5 years...)

```nginx
# cache
proxy_cache_path /tmp/finddqcache keys_zone=finddqcache:10m levels=1:2 inactive=600s max_size=100m;

# (proxy) server
server {
  listen       443 ssl http2;
  listen  [::]:443 ssl http2;
  server_name  ...;

  # SSL
  ssl_certificate     ...;
  ssl_certificate_key ...;

  # Logging
  access_log ...;
  error_log  ... alert;

  root       .../public/;

  location / {
    proxy_set_header Connection ""; # Enable keepalives
    proxy_set_header Referer "";    # WHY DO WE NEED TO DO THIS? We get 403s when we send Referer: headers to Passenger for some reason!
    proxy_set_header Accept-Encoding ""; # Optimize encoding
    proxy_pass http://127.0.0.1:4863;
    proxy_set_header X-Forwarded-For $remote_addr;
  }

  # cache only specifically-fuzzy URLs to avoid cache leaking
  location /fuzzy {
    proxy_set_header Connection ""; # Enable keepalives
    proxy_set_header Accept-Encoding ""; # Optimize encoding
    proxy_set_header Referer "";    # WHY DO WE NEED TO DO THIS? We get 403s when we send Referer: headers to Passenger for some reason!
    proxy_pass http://127.0.0.1:4863;
    proxy_cache finddqcache;        # use the cache defined above
    proxy_cache_valid 200 30s;      # cache for 30 seconds
    proxy_cache_lock on;            # don't let multiple processes write to the cache simultaneously
    proxy_cache_use_stale updating; # if cache outdated, serve outdated response and update in background
    proxy_set_header X-Forwarded-For $remote_addr;
  }

  # cache all maps
  location /maps {
    proxy_set_header Connection ""; # Enable keepalives
    proxy_set_header Accept-Encoding ""; # Optimize encoding
    proxy_set_header Referer "";    # WHY DO WE NEED TO DO THIS? We get 403s when we send Referer: headers to Passenger for some reason!
    proxy_pass http://127.0.0.1:4863;
    proxy_cache finddqcache;        # use the cache defined above
    proxy_cache_valid 200 3h;       # cache for 3 hours
    proxy_cache_lock on;            # don't let multiple processes write to the cache simultaneously
    proxy_cache_use_stale updating; # if cache outdated, serve outdated response and update in background
    proxy_set_header X-Forwarded-For $remote_addr;
  }

  # Remove rule about frameset embedding; we want to do this!
  more_clear_headers "x-frame-options";
}

# we use a separate (local only) vhost and proxy TO it to allow us to use nginx's caching features
server {
  listen 127.0.0.1:4863;
  root       .../public/;

  passenger_enabled              on;
  passenger_ruby                 .../.rvm/gems/ruby-2.6.3@some-gemset/wrappers/ruby;
}
```

## License

Licensed under the BSD 2-Clause "Simplified" License. See `LICENSE`.

