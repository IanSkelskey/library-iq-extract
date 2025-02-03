#!/usr/bin/perl

# Copyright (C) 2024 Bibliomation Inc.
#
# This program is free software; you can redistribute it and/or modify it under the terms of the 
# GNU General Public License as published by the Free Software Foundation; either version 2 of the 
# License, or (at your option) any later version.

use strict;
use warnings;
use Getopt::Long;
use File::Spec;
use XML::Simple;

use lib 'lib';  # or the path to your local modules
use DB qw(get_dbh);
use SFTP qw(do_sftp_upload);
use Email qw(send_email);
use Logging qw(logmsg);
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
use Utils qw(read_config get_last_run_time set_last_run_time process_data_type get_db_config get_org_units create_tar_gz create_history_table);

###########################
# 1) Parse Config & CLI
###########################
my $config_file = 'config/library_config.conf';
my $evergreen_config_file = '/openils/conf/opensrf.xml';
my $debug;
my $full;
my $no_email;
my $no_sftp;
GetOptions(
    "config=s" => \$config_file,
    "evergreen-config=s" => \$evergreen_config_file,
    "debug"    => \$debug,
    "full"     => \$full,
    "no-email" => \$no_email,
    "no-sftp"  => \$no_sftp,
);

my %conf = %{ read_config($config_file, 'libraryiq.log', $debug) };
my $log_file = $conf{logfile} || 'libraryiq.log';

logmsg("Configuration loaded: ".join(',', map { "$_=$conf{$_}" } keys %conf), $log_file, $debug);

logmsg("Library Name(s): $conf{libraryname}", $log_file, $debug);

# Verify that required configuration values are set
die "Configuration value 'libraryname' is missing" unless $conf{libraryname};
die "Configuration value 'logfile' is missing" unless $conf{logfile};

###########################
# 2) DB Connection
###########################
my $db_config = get_db_config($evergreen_config_file);
my $dbh = get_dbh($db_config);
logmsg("Connected to DB", $log_file, $debug);

###########################
# 3) Ensure History Table Exists
###########################
create_history_table($dbh, $log_file, $debug);

###########################
# 4) Get Organization Units
###########################
my $libraryname = $conf{libraryname};
logmsg("Library name: $libraryname", $log_file, $debug);
my $include_descendants = exists $conf{include_org_descendants};
my $org_units = get_org_units($dbh, $libraryname, $include_descendants, sub { logmsg($_[0], $log_file, $debug) });
my $pgLibs = join(',', @$org_units);

###########################
# 5) Figure out last run vs full
###########################
my $last_run_time = get_last_run_time($dbh, \%conf, \&logmsg);
my $run_date_filter = $full ? undef : $last_run_time;
logmsg("Run mode: " . ($full ? "FULL" : "INCREMENTAL from $last_run_time"), $log_file, $debug);

###########################
# 6) For each data type, we:
#   a) get IDs in chunks
#   b) for each chunk, fetch details
#   c) write data to a file
###########################

# Process BIBs
my $bib_out_file = process_data_type(
    'bibs',
    get_bib_ids_sql($full, $pgLibs),
    get_bib_detail_sql(),
    [qw/id isbn upc mat_type pubdate publisher title author/],
    $dbh,
    $run_date_filter,
    $conf{chunksize},
    $conf{tempdir},
    $log_file,
    $debug
);

# Process Items
my $item_out_file = process_data_type(
    'items',
    get_item_ids_sql($full, $pgLibs),
    get_item_detail_sql(),
    [qw/itemid barcode isbn upc bibid collection_code mattype branch_location owning_location call_number shelf_location create_date status last_checkout last_checkin due_date ytd_circ_count circ_count/],
    $dbh,
    $run_date_filter,
    $conf{chunksize},
    $conf{tempdir},
    $log_file,
    $debug
);

# Process Circs
my $circ_out_file = process_data_type(
    'circs',
    get_circ_ids_sql($full, $pgLibs),
    get_circ_detail_sql(),
    [qw/itemid barcode bibid checkout_date checkout_branch patron_id due_date checkin_date/],
    $dbh,
    $run_date_filter,
    $conf{chunksize},
    $conf{tempdir},
    $log_file,
    $debug
);

# Process Patrons
my $patron_out_file = process_data_type(
    'patrons',
    get_patron_ids_sql($full, $pgLibs),
    get_patron_detail_sql(),
    [qw/id expire_date shortname create_date patroncode status ytd_circ_count prev_year_circ_count total_circ_count last_activity last_checkout street1 street2 city state post_code/],
    $dbh,
    $run_date_filter,
    $conf{chunksize},
    $conf{tempdir},
    $log_file,
    $debug
);

# Process Holds
my $hold_out_file = process_data_type(
    'holds',
    get_hold_ids_sql($full, $pgLibs),
    get_hold_detail_sql(),
    [qw/bibrecordid pickup_lib shortname/],
    $dbh,
    $run_date_filter,
    $conf{chunksize},
    $conf{tempdir},
    $log_file,
    $debug
);

###########################
# 7) Create tar.gz archive
###########################
my @output_files = ($bib_out_file, $item_out_file, $circ_out_file, $patron_out_file, $hold_out_file);
my $tar_file = create_tar_gz(\@output_files, $conf{archive}, $conf{filenameprefix}, $log_file, $debug);

###########################
# 8) SFTP upload & Email
###########################
my $sftp_error;
unless ($no_sftp) {
    $sftp_error = do_sftp_upload(
        $conf{ftphost}, 
        $conf{ftplogin}, 
        $conf{ftppass}, 
        $conf{remote_directory}, 
        $tar_file,
        sub { logmsg($_[0], $log_file, $debug) }
    );

    if ($sftp_error) {
        logmsg("SFTP ERROR: $sftp_error", $log_file, $debug);
    } else {
        logmsg("SFTP success", $log_file, $debug);
    }
}

unless ($no_email) {
    # Minimal email
    my @recipients = split /,/, $conf{alwaysemail};  # or success/fail lists
    send_email(
        $conf{fromemail},
        \@recipients,
        "LibraryIQ Extract - ".($full ? "FULL" : "INCREMENTAL"),
        ($sftp_error ? "FAILED with: $sftp_error" : "SUCCESS"),
    );
}

exit 0;