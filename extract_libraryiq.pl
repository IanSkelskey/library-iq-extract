#!/usr/bin/perl

# =============================================================================
# LibraryIQ Extract Script
# Author: Ian Skelskey
# Copyright (C) 2024 Bibliomation Inc.
#
# This script extracts data from Evergreen ILS and sends it to LibraryIQ.
# For use in cases when your security policy does not allow direct access to
# the database. The script can be run on a server with access to the database
# and the extracted data can be sent to LibraryIQ via SFTP.
#
# This program is free software; you can redistribute it and/or modify it 
# under the terms of the GNU General Public License as published by the 
# Free Software Foundation; either version 2 of the License, or (at your 
# option) any later version.
# =============================================================================

use strict;
use warnings;
# use File::Spec;
# use XML::Simple;

use lib 'lib';  # or the path to your local modules
use DBUtils qw(get_dbh get_db_config create_history_table get_org_units get_last_run_time set_last_run_time chunked_ids fetch_data_by_ids drop_schema);
# use SFTP qw(do_sftp_upload);
use Email qw(send_email);
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
	get_inhouse_ids_sql
	get_inhouse_detail_sql
	);

use Utils qw(read_config read_cmd_args check_config check_cmd_args write_data_to_file create_tar_gz);

###########################
# 1) Parse Config & CLI
###########################

logheader("Reading Configuration and CLI Arguments");

# Read command line arguments
my ($config_file, $evergreen_config_file, $debug, $full, $no_email, $no_sftp, $drop_history) = read_cmd_args();

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

# Drop and recreate the libraryiq schema if --drop-history is specified
if ($drop_history) {
    drop_schema($dbh);
    logmsg("SUCCESS", "Dropped existing LibraryIQ schema.");
}

create_history_table($dbh, $log_file, $debug);

###########################
# 4) Get Organization Units
###########################
my $librarynames = $conf->{librarynames};
logmsg("INFO", "Library names: $librarynames");
my $include_descendants = exists $conf->{include_org_descendants};
my $org_units = get_org_units($dbh, $librarynames, $include_descendants);
my $pgLibs = join(',', @$org_units);
logmsg("INFO", "Organization units: $pgLibs");

###########################
# 5) Figure out last run vs full
###########################
my $last_run_time = get_last_run_time($dbh, $conf);
my $run_date_filter = $full ? undef : $last_run_time;
logheader("Run mode: " . ($full ? "FULL" : "INCREMENTAL from $last_run_time"));

###########################
# 6) Process Data Types
###########################

sub get_data {
    my ($id_sql, $detail_sql, @extra_params) = @_;

    # Get chunks of IDs based on the provided SQL query and date filter
    my @chunks = chunked_ids($dbh, $id_sql, $run_date_filter, $conf->{chunksize});
	logmsg("INFO", "Found ".(scalar @chunks)." ID chunks for $id_sql");
	logmsg("INFO", "Detail SQL: $detail_sql");

    my @data;
    # Process each chunk of IDs
    foreach my $chunk (@chunks) {
        # Fetch data for the current chunk of IDs
        my @rows = fetch_data_by_ids($dbh, $chunk, $detail_sql, @extra_params);
        push @data, @rows;
    }

    return @data;
}

sub process_datatype {
    my ($datatype, $id_sql, $detail_sql, $fields, @extra_params) = @_;
    my @data = get_data($id_sql, $detail_sql, @extra_params);
    return write_data_to_file($datatype, \@data, $fields, $conf->{tempdir});
}

# Define a very old date for full runs
my $very_old_date = '1900-01-01';

# Process BIBs
my $bib_out_file = process_datatype(
    'bibs',
    get_bib_ids_sql($full, $pgLibs),
    get_bib_detail_sql(),
    [qw/id isbn upc mat_type pubdate publisher title author/],
    $full ? ($very_old_date, $very_old_date) : ($last_run_time, $last_run_time)
);

# Process Items
my $item_out_file = process_datatype(
    'items',
    get_item_ids_sql($full, $pgLibs),
    get_item_detail_sql(),
    [qw/itemid barcode isbn upc bibid collection_code mattype branch_location owning_location call_number shelf_location create_date status last_checkout last_checkin due_date ytd_circ_count circ_count/],
    $full ? ($very_old_date, $very_old_date) : ($last_run_time, $last_run_time)
);

# Process Circs
my $circ_out_file = process_datatype(
    'circs',
    get_circ_ids_sql($full, $pgLibs),
    get_circ_detail_sql(),
    [qw/itemid barcode bibid checkout_date checkout_branch patron_id due_date checkin_time/],
    $full ? ($very_old_date) : ($last_run_time)
);

# Process Patrons
my $patron_out_file = process_datatype(
    'patrons',
    get_patron_ids_sql($full, $pgLibs),
    get_patron_detail_sql(),
    [qw/id expire_date shortname create_date patroncode status ytd_circ_count prev_year_circ_count total_circ_count last_activity last_checkout street1 street2 city state post_code/],
    $full ? ($very_old_date, $very_old_date) : ($last_run_time, $last_run_time)
);

# Process Holds
my $hold_out_file = process_datatype(
    'holds',
    get_hold_ids_sql($full, $pgLibs),
    get_hold_detail_sql(),
    [qw/bibrecordid pickup_lib shortname/],
    $full ? ($very_old_date) : ($last_run_time)
);

# Process Inhouse
my $inhouse_out_file = process_datatype(
    'inhouse',
    get_inhouse_ids_sql($full, $pgLibs),
    get_inhouse_detail_sql(),
    [qw/itemid barcode bibid checkout_date checkout_branch/],
    $full ? ($very_old_date) : ($last_run_time)
);

###########################
# 7) Create tar.gz archive
###########################
my @output_files = ($bib_out_file, $item_out_file, $circ_out_file, $patron_out_file, $hold_out_file, $inhouse_out_file);
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

unless ($no_email) {
	# Minimal email
	my @recipients = split /,/, $conf->{alwaysemail};  # or success/fail lists
	my $subject = "LibraryIQ Extract - " . ($full ? "FULL" : "INCREMENTAL");
	my $body = "LibraryIQ Extract has completed.";
	send_email(
		$conf->{fromemail},
		\@recipients,
		$subject,
		$body
	);
	logmsg("INFO", "Email sent to: ".join(',', @recipients)
		." from: ".$conf->{fromemail}
		." with subject: $subject"
		." and body: $body");
}

###########################
# 9) Update last run time & cleanup
###########################

set_last_run_time($dbh, $conf);

logheader("Finished Library IQ Extract");

exit 0;
