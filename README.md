silent_corruption_detector
==========================

Early warning detector for silent data corruption [a.k.a. bit rot]

The goal of this program is to serve as a simple early warning detector for silent data corruption. This program verifies the integrity of current (live) files to previously recorded SHA1 checksums.

Assumptions
==========================
1. Different mtime (modified times) is assumed to indicate that any changes to a file were intentional
2. No unintentional corruption happens at the same time an mtime record is updated
3. Silent corruption has not propagated to the backups yet
4. Corruption does not result in the entire loss of the file record [because only live accessible files are scanned]

How it works
==========================
For every live file, a SHA1 hash is generated and compared to a previous record (if one exists). If the mtime of the live file and previous record are the same, but the SHA1 is different, then there may have been some unintended corruption.

Previous records are stored in a SQLite database, by default in a data.db file in the same directory as this script. There are two tables:
1. Meta  -- a key value table used for general purpose configuration data. At this time, it's only used to store the current iteration number.
2. Files -- Path, hash, and a few other file metadata bits are stored here and used for the comparison to live files

As of version 1.0 the database "leaks". When a file is deleted, the corresponding record in the database is NOT deleted. This is not a critical problem, but will lead to an ever increasing database over time. A manual cleanup can be performed in an unsafe manner using an older iteration number as criteria, but this feature might be added later

Usage
==========================
./silent_corruption_detector.rb [START PATH]

If no [START PATH] is provided, the default will use the root (/) directory

License
==========================
See the LICENSE file for additional information.
Copyright (c) 2013 Jon Stacey. All Rights Reserved.

Disclaimer
==========================
This script is provided "AS-IS" with no warranty or guarantees.

Changelog
==========================
1.0 2013-09-20 Completed