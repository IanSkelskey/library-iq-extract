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
use DBUtils qw(get_dbh get_db_config create_history_table get_org_units get_last_run_time get_data);
# use SFTP qw(do_sftp_upload);
# use Email qw(send_email);
use Logging qw(init_logging logmsg logheader);
use Queries qw(
	get_bib_ids_sql
	get_bib_detail_sql
    get_item_ids_sql
    get_item_detail_sql
	get_circ_ids_sql
	get_circ_detail_sql
	get_patron_ids_sql
	get_patron_detail_sql
	get_hold_ids_sql
	get_hold_detail_sql
	);

use Utils qw(read_config read_cmd_args check_config check_cmd_args write_data_to_file create_tar_gz);

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

###########################
# 5) Figure out last run vs full
###########################
my $last_run_time = get_last_run_time($dbh, $conf, \&logmsg);
my $run_date_filter = $full ? undef : $last_run_time;
logheader("Run mode: " . ($full ? "FULL" : "INCREMENTAL from $last_run_time"));

###########################
# 6) For each data type, we:
#   a) get IDs in chunks
#   b) for each chunk, fetch details
#   c) write data to a file
###########################

# Process BIBs
my @bib_data = get_data(
	get_bib_ids_sql($full, $pgLibs),
	get_bib_detail_sql(),
	$dbh,
	$run_date_filter,
	$conf->{chunksize}
);

my $bib_out_file = write_data_to_file(
	'bibs',
	\@bib_data,
	[qw/id isbn upc mat_type pubdate publisher title author/],
	$conf->{tempdir}
);

# Process Items
my @item_data = get_data(
	get_item_ids_sql($full, $pgLibs),
	get_item_detail_sql(),
	$dbh,
	$run_date_filter,
	$conf->{chunksize}
);

my $item_out_file = write_data_to_file(
	'items',
	\@item_data,
	[qw/itemid barcode isbn upc bibid collection_code mattype branch_location owning_location call_number shelf_location create_date status last_checkout last_checkin due_date ytd_circ_count circ_count/],
	$conf->{tempdir}
);

# Process Circs
my @circ_data = get_data(
	get_circ_ids_sql($full, $pgLibs),
	get_circ_detail_sql(),
	$dbh,
	$run_date_filter,
	$conf->{chunksize}
);

my $circ_out_file = write_data_to_file(
	'circs',
	\@circ_data,
	[qw/itemid barcode bibid checkout_date checkout_branch patron_id due_date checkin_date/],
	$conf->{tempdir}
);

# Process Patrons
my @patron_data = get_data(
	get_patron_ids_sql($full, $pgLibs),
	get_patron_detail_sql(),
	$dbh,
	$run_date_filter,
	$conf->{chunksize}
);

my $patron_out_file = write_data_to_file(
	'patrons',
	\@patron_data,
	[qw/id expire_date shortname create_date patroncode status ytd_circ_count prev_year_circ_count total_circ_count last_activity last_checkout street1 street2 city state post_code/],
	$conf->{tempdir}
);

# Process Holds
my @hold_data = get_data(
	get_hold_ids_sql($full, $pgLibs),
	get_hold_detail_sql(),
	$dbh,
	$run_date_filter,
	$conf->{chunksize}
);

my $hold_out_file = write_data_to_file(
	'holds',
	\@hold_data,
	[qw/bibrecordid pickup_lib shortname/],
	$conf->{tempdir}
);

###########################
# 7) Create tar.gz archive
###########################
my @output_files = ($bib_out_file, $item_out_file, $circ_out_file, $patron_out_file, $hold_out_file);
my $tar_file = create_tar_gz(\@output_files, $conf->{archive}, $conf->{filenameprefix});

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

logheader("Finished Library IQ Extract");

exit 0;