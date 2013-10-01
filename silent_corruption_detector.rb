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
    
    @bytes_processed    = 0
    @files_processed    = 0
    @total_bytes        = 0
    @files              = Array.new
    @current_file       = String.new
    @iteration          = nil # placeholder -- so you know that iteration is an availabe instance variable
    @last_msg_was_alert = false
  end
  
  # Even single threaded, this is still IO-bound. I push around 70% single core usage at my max 200MB/s steady state read rate on a 2.8GHz Intel i5.
  def hash(file)
    digest     = Digest::SHA1.new
    # filesize   = File.size(file)
    # bytes_read = 0
    buffer     = String.new

    begin
      io = File.open(file, "rb")
      until io.eof?
        io.read(16384, buffer)
        digest << buffer
        # bytes_read       += buffer.bytesize
        @bytes_processed += buffer.bytesize
      end
    rescue => e
      puts "Notice:".red.on_yellow + " Unexpected error reading #{file}: #{e}. Skipping."
      @last_msg_was_alert = true
      return nil
    ensure
      io.close unless io.nil?
    end
  
    return digest.hexdigest
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
      @DB[:files].where(file: file).update(hash: hash(file), mtime: File.mtime(file), iteration: @iteration, updated_at: Time.now)
    end
  end
  
  def bump_iteration
    # Increment and retrieve the current iteration number
    @iteration = @DB[:Meta].where(key: 'iteration').first[:value].to_i + 1
    @DB[:Meta].where(key: 'iteration').update value: @iteration
  end
  
  def show_progress
    # "\e[A" moves cursor up one line
    # "\e[K" clears from the cursor position to the end of the line
    # "\r" moves the cursor to the start of the line
    
    # Clear the last 3 lines of the console
    if @last_msg_was_alert
      @last_msg_was_alert = false
    else
      print "\r\e[K"
      print "\e[A\e[K" * 3
    end
    
    print "Current File   : #{@current_file}\n"
    print "Total Processed: #{number_with_delimiter(@files_processed)} / #{number_with_delimiter(@files.count)} files\n"
    print "Total Progress : " + 
          "#{number_to_percentage((@bytes_processed.to_f / @total_bytes.to_f)*100, precision: 2)}".green.bold + 
          " (#{number_to_human_size(@bytes_processed)} / #{number_to_human_size(@total_bytes)})\n"
  end
  
  def iterate
    bump_iteration
    
    @files.each do |file|
      @files_processed += 1
      @current_file     = file
      db_record         = @DB[:files].where file: file
      
      if db_record.count == 0
        create_record(file) 
      else
        # Compare the record only if the database iteration is less than the current iteration
        # This is because files may have multipl links pointing to them and we only want to scan them once
        compare_record(file, db_record) if db_record.first[:iteration] < @iteration
      end
    end
    
    Thread.exit
  end
  
  def collect_inventory
    Find.find(@START_PATH) do |path|
      next if File.directory? path # Exclude directories
      begin
        @files << File.realpath(path)   # Use the true real path
        @total_bytes += File.size path
      rescue
        next # The full path can't be resolved for some reason, probably because this is a broken symlink, so skip.
      end
    end
  end
  
  def _show_collection_progress
    print "\r\e[KApproximately #{number_with_delimiter(@files.count)} files (#{number_to_human_size(@total_bytes)}) to analyze."
  end
  
  def _run_worker(worker_method, progress_method, trailing_progress = true, frequency = 1)
    worker = Thread.new { self.send(worker_method) }
    until worker.status == false
      self.send progress_method
      sleep 1
    end
    self.send progress_method if trailing_progress
  end

  def run
    puts "Collecting Inventory . . ."
    _run_worker :collect_inventory, :_show_collection_progress
    
    puts ""
    print '-' * 50
    print "\n" * 4
    
    _run_worker :iterate, :show_progress
    
    puts ""
    print '=' * 50
    puts "\nDone! Checked the integrity of #{number_with_delimiter(@files_processed)} files. Possible silent data corruption will be noted in the output above, if any."
  end
  
end

detector = SilentDataCorruptionDetector.new(ARGV[0].nil? ? DEFAULT_START_PATH : ARGV[0], DATABASE_FILE)
detector.run