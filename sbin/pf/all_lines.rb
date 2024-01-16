#!/usr/local/bin/ruby
require 'json'
require 'wikk_configuration'
require 'wikk_json'
RLIB = '/wikk/rlib' unless defined? RLIB
require_relative "#{RLIB}/wikk_conf.rb"

@line_ctl = WIKK::Configuration.new("#{PF_CONF_DIR}/line_state.json")
@num_lines = @line_ctl.line.length - 1

lines = []
(1..@num_lines).each do |i| # Skip 0, as we start numbering dsl modems at 1, while the array numbers from 0
  lines << i
end
puts lines.join(' ')
