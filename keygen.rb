#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'
require 'dotenv/load'
Dotenv.require_keys('KEY_PROTECTOR')
require 'digest/sha2'
require 'base64'

from, to = ARGV
unless from && to
  puts 'Syntax:'
  puts '  ./keygen.rb <start datetime> <end datetime>'
  puts '  ./keygen.rb "2020-01-01 10:00:00" "2020-02-02 09:30:00"'
  exit
end

signature = Digest::SHA256.hexdigest([from, to, ENV['KEY_PROTECTOR']].join('/'))
puts Base64.urlsafe_encode64([from, to, signature].join('!'), padding: false)
