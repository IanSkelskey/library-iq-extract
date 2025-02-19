#!/usr/bin/perl

# Copyright (C) 2024 Bibliomation Inc.
#
# This program is free software; you can redistribute it and/or modify it under the terms of the 
# GNU General Public License as published by the Free Software Foundation; either version 2 of the 
# License, or (at your option) any later version.

use strict;
use warnings;
# use File::Spec;
# use XML::Simple;

use lib 'lib';  # or the path to your local modules
use DBUtils qw(get_dbh get_db_config create_history_table get_org_units);
# use SFTP qw(do_sftp_upload);
# use Email qw(send_email);
use Logging qw(init_logging logmsg);
# use Queries qw(
#     get_bib_ids_sql
#     get_bib_detail_sql
#     get_item_ids_sql
#     get_item_detail_sql
#     get_circ_ids_sql
#     get_circ_detail_sql
#     get_patron_ids_sql
#     get_patron_detail_sql
#     get_hold_ids_sql
#     get_hold_detail_sql
# );
use Utils qw(read_config read_cmd_args check_config check_cmd_args);

###########################
# 1) Parse Config & CLI
###########################
# Read command line arguments
my ($config_file, $evergreen_config_file, $debug, $full, $no_email, $no_sftp) = read_cmd_args();

# Read and check configuration file
my $conf = read_config($config_file);

# Initialize logging
my $log_file = $conf->{logfile};
init_logging($log_file, $debug);

# Check config and CLI values
check_config($conf);
check_cmd_args($config_file);
logmsg("SUCCESS", "Config file and CLI values are valid");

###########################
# 2) DB Connection
###########################
my $db_config = get_db_config($evergreen_config_file);
my $dbh = get_dbh($db_config);
logmsg("SUCCESS", "Connected to DB");

###########################
# 3) Ensure History Table Exists
###########################
create_history_table($dbh, $log_file, $debug);

###########################
# 4) Get Organization Units
###########################
my $librarynames = $conf->{librarynames};
logmsg("INFO", "Library names: $librarynames");
my $include_descendants = exists $conf->{include_org_descendants};
my $org_units = get_org_units($dbh, $librarynames, $include_descendants, sub { logmsg("INFO", $_[0]) });
my $pgLibs = join(',', @$org_units);
logmsg("INFO", "Organization units: $pgLibs");

# ###########################
# # 5) Figure out last run vs full
# ###########################
# my $last_run_time = get_last_run_time($dbh, $conf, \&logmsg);
# my $run_date_filter = $full ? undef : $last_run_time;
# logmsg("Run mode: " . ($full ? "FULL" : "INCREMENTAL from $last_run_time"), $log_file, $debug);

# ###########################
# # 6) For each data type, we:
# #   a) get IDs in chunks
# #   b) for each chunk, fetch details
# #   c) write data to a file
# ###########################

# # Process BIBs
# my $bib_out_file = process_data_type(
#     'bibs',
#     get_bib_ids_sql($full, $pgLibs),
#     get_bib_detail_sql(),
#     [qw/id isbn upc mat_type pubdate publisher title author/],
#     $dbh,
#     $run_date_filter,
#     $conf->{chunksize},
#     $conf->{tempdir},
#     $log_file,
#     $debug
# );

# # Process Items
# my $item_out_file = process_data_type(
#     'items',
#     get_item_ids_sql($full, $pgLibs),
#     get_item_detail_sql(),
#     [qw/itemid barcode isbn upc bibid collection_code mattype branch_location owning_location call_number shelf_location create_date status last_checkout last_checkin due_date ytd_circ_count circ_count/],
#     $dbh,
#     $run_date_filter,
#     $conf->{chunksize},
#     $conf->{tempdir},
#     $log_file,
#     $debug
# );

# # Process Circs
# my $circ_out_file = process_data_type(
#     'circs',
#     get_circ_ids_sql($full, $pgLibs),
#     get_circ_detail_sql(),
#     [qw/itemid barcode bibid checkout_date checkout_branch patron_id due_date checkin_date/],
#     $dbh,
#     $run_date_filter,
#     $conf->{chunksize},
#     $conf->{tempdir},
#     $log_file,
#     $debug
# );

# # Process Patrons
# my $patron_out_file = process_data_type(
#     'patrons',
#     get_patron_ids_sql($full, $pgLibs),
#     get_patron_detail_sql(),
#     [qw/id expire_date shortname create_date patroncode status ytd_circ_count prev_year_circ_count total_circ_count last_activity last_checkout street1 street2 city state post_code/],
#     $dbh,
#     $run_date_filter,
#     $conf->{chunksize},
#     $conf->{tempdir},
#     $log_file,
#     $debug
# );

# # Process Holds
# my $hold_out_file = process_data_type(
#     'holds',
#     get_hold_ids_sql($full, $pgLibs),
#     get_hold_detail_sql(),
#     [qw/bibrecordid pickup_lib shortname/],
#     $dbh,
#     $run_date_filter,
#     $conf->{chunksize},
#     $conf->{tempdir},
#     $log_file,
#     $debug
# );

# ###########################
# # 7) Create tar.gz archive
# ###########################
# my @output_files = ($bib_out_file, $item_out_file, $circ_out_file, $patron_out_file, $hold_out_file);
# my $tar_file = create_tar_gz(\@output_files, $conf->{archive}, $conf->{filenameprefix}, $log_file, $debug);

# ###########################
# # 8) SFTP upload & Email
# ###########################
# my $sftp_error;
# unless ($no_sftp) {
#     $sftp_error = do_sftp_upload(
#         $conf->{ftphost}, 
#         $conf->{ftplogin}, 
#         $conf->{ftppass}, 
#         $conf->{remote_directory}, 
#         $tar_file,
#         sub { logmsg($_[0], $log_file, $debug) }
#     );

#     if ($sftp_error) {
#         logmsg("SFTP ERROR: $sftp_error", $log_file, $debug);
#     } else {
#         logmsg("SFTP success", $log_file, $debug);
#     }
# }

# unless ($no_email) {
#     # Minimal email
#     my @recipients = split /,/, $conf->{alwaysemail};  # or success/fail lists
#     send_email(
#         $conf->{fromemail},
#         \@recipients,
#         "LibraryIQ Extract - ".($full ? "FULL" : "INCREMENTAL"),
#         ($sftp_error ? "FAILED with: $sftp_error" : "SUCCESS"),
#     );
# }

# exit 0;