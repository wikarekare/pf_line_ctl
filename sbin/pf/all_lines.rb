#!/usr/local/bin/ruby
require 'json'
require 'wikk_configuration'
require 'wikk_json'

load '/wikk/etc/wikk.conf' unless defined? WIKK_CONF

@line_ctl = WIKK::Configuration.new("#{PF_CONF_DIR}/line_state.json")
@num_lines = @line_ctl.line.length - 1

lines = Array.new(@num_lines) { |i| i + 1 } # Skip 0, as we start numbering dsl modems at 1, while the array numbers from 0
puts lines.join(' ')
