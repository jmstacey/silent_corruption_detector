#!/usr/bin/env ruby 

# =Silent Corruption Detector
#
# Version:: 1.0 | September 28, 2013
# Author:: Jon Stacey
# Email:: use the contact form at jonsview.com/contact
# Website:: jonsview.com
#
# ==Description
# The goal of this program is to serve as a simple early warning detector for silent data corruption. This program verifies the integrity of current (live) files to previously recorded SHA1 checksums.
#
# Assumptions:
# (1) Different mtime (modified times) is assumed to indicate that any changes to a file were intentional
# (2) No unintentional corruption happens at the same time an mtime record is updated
# (3) Silent corruption has not propagated to the backups yet
# (4) Corruption does not result in the entire loss of the file record [because only live accessible files are scanned]
#
# How it works:
# (1) Look at every live file and compare its SHA1 hash to a previous record (if one exists)
# (2) If the mtime of the live file and previous record are the same, but the SHA1 is different, then there may have been some unintended data corruption.
#
# ==Usage
# ./silent_corruption_detector.rb [START PATH]
#
# If no [START PATH] is provided, the default will use the root (/) directory
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
# 1.0 2013-09-20 Completed

require 'find'
require 'time'
require 'digest'
require 'sqlite3'
require 'sequel'
require 'colorize'
require 'action_view'

include ActionView::Helpers::NumberHelper

DEFAULT_START_PATH = "/"
DATABASE_FILE      = "data.db"

class SilentDataCorruptionDetector
  
  def initialize(start_path, db_file)
    @DB = Sequel.sqlite db_file
    
    # Create the database schema if needed
    @DB.create_table? :meta do
      String :key,   null: false, unique: true
      String :value, null: true
    end
    
    @DB[:meta].insert key: 'iteration', value: '0' unless @DB[:Meta].where(key: 'iteration').count > 0
    
    @DB.create_table? :files do
      primary_key :id
      String      :file,            text: true, null: false, unique: true
      String      :hash,            text: true, null: false
      DateTime    :mtime,           null: false
      Integer     :iteration,       null: false
      DateTime    :created_at,      null: false
      DateTime    :updated_at,      null: false
      index       :file,          unique: true
      index       [:file, :hash], unique: true
    end
    
    # Initialize the start path
    @START_PATH = start_path
    
    @bytes_processed = 0
    @files_processed = 0
    @iteration       = nil # placeholder -- so you know that iteration is an instance variable
    @current_file    = String.new
  end

  # def hash(file)
  #   digest = Digest::SHA1.new
  # 
  #   begin
  #     open(file, "r") do |io|
  #       while (!io.eof)
  #         read_buffer = io.readpartial(4096)
  #         # digest.update(read_buffer)
  #       end
  #     end
  #   rescue => e
  #     puts "Warning: Unexpected error reading #{file}: #{e}. Skipping."
  #     return nil
  #   end
  # 
  #   digest.hexdigest
  # end
  
  # This variation is significantly faster than the above because there's less data thrashing--moving data into high level buffer and back out.
  # Even single threaded, this is still IO-bound. I push around 70% single core usage at my max 200MB/s steady state read rate on a 2.8GHz Intel i5.
  def hash(file)
    begin
      digest = Digest::MD5.file file
      @bytes_processed += File.size?(file).to_i
    rescue => e
      puts "Warning:".red.on_yello + " Unexpected error reading #{file}: #{e}. Skipping."
      @last_msg_was_alert = true
      return nil
    end
  
    digest.hexdigest
  end
  
  def create_record(file)
    hash = hash(file)
    return if hash.nil?
    
    # Create the DB new record
    @DB[:files].insert file:       file,
                       hash:       hash,
                       mtime:      File.mtime(file),
                       iteration:  @iteration,
                       created_at: Time.now,
                       updated_at: Time.now
  end
  
  def compare_record(file, db_record)
    if File.mtime(file) == db_record.first[:mtime]
      # mtime looks the same, so we expect the hash to be the same [no intentional changes]
      if db_record.first[:hash] != hash(file)
        puts "!!! ALERT !!!".white.on_red.bold.blink + " Possible silent corruption on #{file}. The mtime is the same, but hash differs from record."
        @last_msg_was_alert = true
      end
    else
      # mtime looks different, so we expect the hash _could_ intentionally be different, so just update the DB
      @DB[:files].where(file: file).update(mtime: File.mtime(file), iteration: @iteration, updated_at: Time.now)
    end
  end
  
  def bump_iteration
    # Increment and retrieve the current iteration number
    @iteration = @DB[:Meta].where(key: 'iteration').first[:value].to_i + 1
    @DB[:Meta].where(key: 'iteration').update value: @iteration
  end
  
  def show_progress(total_file_count)
    # "\e[A" moves cursor up one line
    # "\e[K" clears from the cursor position to the end of the line
    # "\r" moves the cursor to the start of the line
    
    # Clear the last 3 lines of the console
    if @files_processed > 1 && !@last_msg_was_alert
      print "\r\e[K"
      print "\e[A\e[K" * 3
    else
      @last_msg_was_alert = false
    end
    
    print "Current File   : #{@current_file}\n"
    print "Total Processed: #{number_to_human_size(@bytes_processed)}\n"
    print "Total Progress : " + 
          "#{number_to_percentage((@files_processed.to_f / total_file_count.to_f)*100, precision: 2)}".green.bold + 
          " (#{number_with_delimiter(@files_processed)} / #{number_with_delimiter(total_file_count)} records)\n"
  end
  
  def iterate(files)
    bump_iteration
    
    files.each do |file|
      @files_processed += 1
      
      next if File.directory? file
      
      @current_file = file
      db_record     = @DB[:files].where file: file
      
      if db_record.count == 0
        create_record(file) 
      else
        compare_record(file, db_record)
      end
    end
    
    Thread.exit
  end

  def run
    puts "Collecting Live Inventory . . ."
    files = Find.find(@START_PATH)
    
    puts "Approximately #{number_with_delimiter(files.count)} live records to analyze"
    print '-' * 50
    print "\n" * 4
    
    worker = Thread.new { iterate files }
    until worker.status == false
      show_progress(files.count)
      sleep 1
    end
  
    puts ""
    print '=' * 50
    puts "\nDone! Checked the integrity of #{number_with_delimiter(@files_processed)} records. Possible silent data corruption will be noted in the output above, if any."
  end
  
end

detector = SilentDataCorruptionDetector.new(ARGV[0].nil? ? DEFAULT_START_PATH : ARGV[0], DATABASE_FILE)
detector.run