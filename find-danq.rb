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
set :allow_origin, 'https://danq.me https://bloq.danq.me'
set :allow_methods, 'GET,HEAD'

#### Tweak ENV var types ####

FUZZ_FACTOR = ENV['FUZZ_FACTOR'].to_i
DRIFT_SEED_SALT = ENV['DRIFT_SEED_SALT'].to_i
DRIFT_FACTOR = ENV['DRIFT_FACTOR'].to_i

#### Convenience functions ####

TRUSTED_IPS = (ENV['TRUSTED_IPS'] || '').split(',')
def authenticated?(key = '')
  # If a key is provided, use that FIRST (this makes it easier to see what unauthenticated people would see simply by providing an invalid key)
  if key && (key != '')
    begin
      from, to, signature = Base64.urlsafe_decode64(key).split('!', 3)
      return false unless from && to && signature
      valid_signature = Digest::SHA256.hexdigest([from, to, ENV['KEY_PROTECTOR']].join('/'))
      return false unless signature == valid_signature
      from, to, now = Time.parse(from), Time.parse(to), Time.now
      return true if (from < Time.now) && (Time.now < to)
    rescue ArgumentError
      return false
    end
  end
  # If no key is provided, check for a trusted IP address
  TRUSTED_IPS.include?(request.ip)
end

def get_loc
  authenticated = authenticated?(params[:key])
  db = Mysql2::Client.new(host: ENV['DB_HOST'], username: ENV['DB_USERNAME'], password: ENV['DB_PASSWORD'], database: ENV['DB_DATABASE'])
  loc = db.query("SELECT UNIX_TIMESTAMP(time) AS unix, DATE_FORMAT(CONVERT_TZ(time, @@SESSION.time_zone, '+00:00'), '%W') AS dow, DATE_FORMAT(CONVERT_TZ(time, @@SESSION.time_zone, '+00:00'), '%a %e %b %Y, %H:%i UTC') AS time, latitude, longitude, accuracy FROM positions ORDER BY id DESC LIMIT 1").first
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

#### Routes ####

get '/' do
  erb :index
end

get '/location.png' do
  loc = get_loc
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
  redirect "/#{file}"
end

get '/location.json' do
  content_type 'application/json'
  get_loc.to_json
end
