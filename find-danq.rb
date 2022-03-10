#!/home/dan/.rvm/gems/ruby-2.6.3@find-danq/wrappers/ruby
require 'rubygems'
require 'bundler/setup'
Bundler.require
require 'dotenv/load'
Dotenv.require_keys('FUZZ_FACTOR', 'DRIFT_SEED_SALT', 'DRIFT_FACTOR', 'GOOGLE_MAPS_GEOCODING_API_KEY', 'DB_HOST', 'DB_USERNAME', 'DB_PASSWORD', 'DB_DATABASE')
require 'json'
require 'open-uri'
require 'digest/sha2'
require 'base64'
require 'time'

### CORS ###
set :allow_origin, 'https://danq.me https://bloq.danq.me https://fox.q-t-a.uk'
set :allow_methods, 'GET,HEAD'

#### Tweak ENV var types ####

FUZZ_FACTOR = ENV['FUZZ_FACTOR'].to_i
DRIFT_SEED_SALT = ENV['DRIFT_SEED_SALT'].to_i
DRIFT_FACTOR = ENV['DRIFT_FACTOR'].to_i

#### Convenience functions ####

TRUSTED_IPS = (ENV['TRUSTED_IPS'] || '').split(',') + (ENV['TRUSTED_DOMAINS'] || '').split(',').map{|d| `dig +short #{d}`.strip }
def authenticated?(key = '')
  # If a key is provided, use that FIRST (this makes it easier to see what unauthenticated people would see simply by providing an invalid key)
  if key && (key != '')
    begin
      now = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      from, to, signature = Base64.urlsafe_decode64(key).split('!', 3)
      return false unless from && to && signature
      valid_signature = Digest::SHA256.hexdigest([from, to, ENV['KEY_PROTECTOR']].join('/'))
      return false unless signature == valid_signature
      return (from < now) && (now < to)
    rescue ArgumentError
      return false
    end
  end
  # If no key is provided, check for a trusted IP address
  TRUSTED_IPS.include?(request.ip)
end

def get_db
  Mysql2::Client.new(host: ENV['DB_HOST'], username: ENV['DB_USERNAME'], password: ENV['DB_PASSWORD'], database: ENV['DB_DATABASE'])
end

def get_loc(force_fuzzy: false)
  authenticated = !force_fuzzy && authenticated?(params['key'])
  db = get_db
  loc = db.query("SELECT UNIX_TIMESTAMP(time) AS unix, DATE_FORMAT(CONVERT_TZ(time, @@SESSION.time_zone, '+00:00'), '%W') AS dow, DATE_FORMAT(CONVERT_TZ(time, @@SESSION.time_zone, '+00:00'), '%a %e %b %Y, %H:%i UTC') AS time, latitude, longitude, accuracy FROM positions ORDER BY UNIX_TIMESTAMP(time) DESC LIMIT 1").first
  loc['authenticated'] = authenticated
  begin
    roundedLat, roundedLng = loc['latitude'].round(2), loc['longitude'].round(2)
    geocoding = db.query("SELECT friendly, friendly_limited FROM geocodings WHERE lat=#{roundedLat} AND lng=#{roundedLng}").first
    if geocoding
      loc['friendly'] = authenticated ? geocoding['friendly'] : geocoding['friendly_limited']
    else
      geocoding_uri = "https://maps.googleapis.com/maps/api/geocode/json?latlng=#{roundedLat},#{roundedLng}&language=en-GB&result_type=country|locality&key=#{ENV['GOOGLE_MAPS_GEOCODING_API_KEY']}"
      geocoding = JSON.parse(URI.parse(geocoding_uri).read)
      address_components = geocoding['results'][0]['address_components'].map{|p|p['long_name']}
      friendly = address_components.join(', ')
      friendly_limited = address_components[1...].join(', ')
      db.query("INSERT INTO geocodings(lat, lng, friendly, friendly_limited, updated_at) VALUES(#{roundedLat}, #{roundedLng}, '#{db.escape(friendly)}', '#{db.escape(friendly_limited)}', NOW())")
      loc['friendly'] = authenticated ? friendly : friendly_limited
    end
  rescue
    loc['friendly'] = ''
  end
  loc['accuracy'] ||= 0 # GPS unit doesn't record this, it seems; needs re-adding manually
  unless authenticated
    # Fuzz location
    loc['latitude'] = loc['latitude'].round(FUZZ_FACTOR)
    loc['longitude'] = loc['longitude'].round(FUZZ_FACTOR)
    loc['accuracy'] = loc['accuracy'] + (100000 / 10^FUZZ_FACTOR) + (60000 / DRIFT_FACTOR)
    # Drift location using date component plus a salt as random seed
    srand(loc['time'].to_s[0..9].gsub(/[^\d]/,'').to_i + DRIFT_SEED_SALT)
    loc['latitude'] += (rand() - 0.5) / DRIFT_FACTOR
    loc['longitude'] += (rand() - 0.5) / DRIFT_FACTOR
  end
  loc
end

def get_map(loc)
  lat, lng, zoom, marker = loc['latitude'].round(1), loc['longitude'].round(1), 8, ''
  if loc['authenticated']
    zoom = 14
    lat, lng = loc['latitude'].round(3), loc['longitude'].round(3)
    marker = "&marker=lonlat:#{lng},#{lat};color:%23155a93;size:medium"
  end
  file = "maps/map-#{lat}-#{lng}-#{zoom}.png"
  if !File.exists?("public/#{file}")
    url = "https://maps.geoapify.com/v1/staticmap?style=osm-bright-smooth&width=400&height=400&center=lonlat:#{lng},#{lat}&zoom=#{zoom}&apiKey=#{ENV['GEOAPIFY_API_KEY']}#{marker}"
    http = Curl.get(url)
    File.open("public/#{file}", 'wb'){|f| f.print(http.body_str) }
  end
  file
end

#### Routes ####

get '/' do
  erb :index
end

get '/fuzzy/location.png' do
  loc = get_loc(force_fuzzy: true)
  file = get_map(loc)
  redirect "/#{file}"
end

get '/fuzzy/location.json' do
  content_type 'application/json'
  get_loc(force_fuzzy: true).to_json
end

get '/location.png' do
  loc = get_loc
  file = get_map(loc)
  redirect "/#{file}"
end

get '/location.json' do
  content_type 'application/json'
  get_loc.to_json
end

get '/compass' do
  erb :compass
end

get '/heat' do
  return 'authentication needed' unless authenticated?(params['key'])
  erb :heat
end

get '/heat.json' do
  return 'authentication needed' unless authenticated?(params['key'])
  content_type 'application/json'
  db = get_db
  from = Mysql2::Client.escape(params['from'])
  to = Mysql2::Client.escape(params['to'])
  sql = "
    SELECT ROUND(latitude, 5) lat, ROUND(longitude, 5) lng, POWER(COUNT(*), 3) `count`
    FROM positions
    WHERE `time` BETWEEN '#{from}' AND '#{to}'
    GROUP BY ROUND(latitude, 5), ROUND(longitude, 5)
  "
  db.query(sql).to_a.to_json
end
