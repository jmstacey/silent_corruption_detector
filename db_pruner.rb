#!/usr/bin/env ruby

# =Silent Corruption Detector Database Pruner
#
# Version:: 1.0 | October 29, 2014
# Author:: Jon Stacey
# Email:: use the contact form at jonsview.com/contact
# Website:: jonsview.com
#
# ==Description
# Small utility script that prunes the database of records for files that no longer exist.
#
# ==Usage
# ./silent_corruption_detector.rb [START PATH] [DATABASE FILE]
#
# ==License
# The MIT License (MIT)
#
# Copyright (c) 2013 Jon Stacey
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# ==Disclaimer
# This script is provided "AS-IS" with no warranty or guarantees.
#
# ==Changelog
# 1.0 2013-10-29 Completed

require 'find'
require 'time'
require 'digest'
require 'sqlite3'
require 'sequel'
require 'colorize'
require 'action_view'

include ActionView::Helpers::NumberHelper

I18n.config.enforce_available_locales = false

DEFAULT_DATABASE_FILE  = "data.db"

class SilentDataCorruptionDBPruner

  def initialize(search_path, db_file)
    @DB = Sequel.sqlite db_file, max_connections: 1
    @search_path = search_path
  end

  def _file_or_symlink_exists?(file)
    File.exists?(file) || File.symlink?(file)
  end

  def run
    pruned_records     = 0
    records_processed  = 0
    records_to_process = @DB[:files].count.to_i
    @DB[:files].each do |record|
      records_processed += 1
      puts "#{records_processed} / #{records_to_process} processed. [#{pruned_records} pruned]"

      if File.fnmatch?(@search_path, record[:file])
        unless _file_or_symlink_exists?(record[:file])
          puts "Pruned #{record[:file]}"
          @DB[:files].where(id: record[:id]).delete
          pruned_records += 1
        end
      end
    end

    puts "Done! Pruned #{pruned_records} records."
  end

end

# Main Program

exit unless !ARGV[0].nil? && !ARGV[1].nil?

pruner = SilentDataCorruptionDBPruner.new(ARGV[0], ARGV[1])
pruner.run
