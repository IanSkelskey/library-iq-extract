package Utils;

use strict;
use warnings;
use Exporter 'import';
use File::Spec;
use DBUtils qw(chunked_ids fetch_data_by_ids);
use Logging qw(logmsg);
use Archive::Tar;
use Getopt::Long;

our @EXPORT_OK = qw(read_config read_cmd_args check_config check_cmd_args get_last_run_time set_last_run_time process_data_type get_db_config create_tar_gz dedupe_array);

# ----------------------------------------------------------
# read_config - Read configuration file
# ----------------------------------------------------------
sub read_config {
    my ($file) = @_;
    open my $fh, '<', $file or die "Cannot open config $file: $!";
    my %c;
    while (<$fh>) {
        chomp;
        s/\r//;
        next if /^\s*#/;     # skip comments
        next unless /\S/;    # skip blank lines
        my ($k, $v) = split(/=/, $_, 2);

        # Trim leading/trailing whitespace
        $k =~ s/^\s+|\s+$//g if defined $k;
        $v =~ s/^\s+|\s+$//g if defined $v;

        $c{$k} = $v if defined $k and defined $v;
    }
    close $fh;
    return \%c;
}

# ----------------------------------------------------------
# check_config - Check configuration values
# ----------------------------------------------------------
sub check_config {
    my ($conf) = @_;

    my @reqs = (
        "logfile", "tempdir", "librarynames", "ftplogin",
        "ftppass", "ftphost", "remote_directory", "emailsubjectline",
        "archive", "transfermethod"
    );

    my @missing = ();
    
    for my $i ( 0 .. $#reqs ) {
        push( @missing, $reqs[$i] ) if ( !defined $conf->{ $reqs[$i] } || $conf->{ $reqs[$i] } eq '' );
    }

    if ( $#missing > -1 ) {
        my $msg = "Please specify the required configuration options:\n" . join("\n", @missing) . "\n";
        logmsg("ERROR", $msg);
        die $msg;
    }
    if ( !-e $conf->{"tempdir"} ) {
        my $msg = "Temp folder: " . $conf->{"tempdir"} . " does not exist.\n";
        logmsg("ERROR", $msg);
        die $msg;
    }

    if ( !-e $conf->{"archive"} ) {
        my $msg = "Archive folder: " . $conf->{"archive"} . " does not exist.\n";
        logmsg("ERROR", $msg);
        die $msg;
    }

    if ( lc $conf->{"transfermethod"} ne 'sftp' ) {
        my $msg = "Transfer method: " . $conf->{"transfermethod"} . " is not supported\n";
        logmsg("ERROR", $msg);
        die $msg;
    }
}

# ----------------------------------------------------------
# read_cmd_args - Read and validate command line arguments
# ----------------------------------------------------------
sub read_cmd_args {
    my ($config_file, $evergreen_config_file, $debug, $full, $no_email, $no_sftp) = @_;
    $evergreen_config_file ||= '/openils/conf/opensrf.xml';  # Default value

    GetOptions(
        "config=s"           => \$config_file,
        "evergreen-config=s" => \$evergreen_config_file,
        "debug"              => \$debug,
        "full"               => \$full,
        "no-email"           => \$no_email,
        "no-sftp"            => \$no_sftp,
    );

    return ($config_file, $evergreen_config_file, $debug, $full, $no_email, $no_sftp);
}


# ----------------------------------------------------------
# check_cmd_args - Check command line arguments
# ----------------------------------------------------------
sub check_cmd_args {
    my ($config_file) = @_;

    if ( !-e $config_file ) {
        my $msg = "$config_file does not exist. Please provide a path to your configuration file: --config\n";
        logmsg("ERROR", $msg);
        die $msg;
    }
}

# ----------------------------------------------------------
# get_last_run_time - Get the last run time from the database
# ----------------------------------------------------------
sub get_last_run_time {
    my ($dbh, $c, $log) = @_;
    # You can store last run in a dedicated table, or read from a file, etc.
    my $sql = "SELECT last_run FROM libraryiq.history WHERE key=? LIMIT 1";
    my $sth = $dbh->prepare($sql);
    $sth->execute($c->{libraryname});
    if (my ($ts) = $sth->fetchrow_array) {
        $sth->finish;
        return $ts; # e.g. '2025-01-01'
    } else {
        $sth->finish;
        $log->("No existing entry. Using old date -> 1900-01-01");
        return '1900-01-01';
    }
}

# ----------------------------------------------------------
# set_last_run_time - Set the last run time in the database
# ----------------------------------------------------------
sub set_last_run_time {
    my ($dbh, $c, $log) = @_;
    my $sql_upd = q{
      UPDATE libraryiq.history SET last_run=now() WHERE key=?
    };
    my $sth_upd = $dbh->prepare($sql_upd);
    my $rows = $sth_upd->execute($c->{libraryname});
    if ($rows == 0) {
      # Might need an INSERT if row does not exist
      my $sql_ins = q{
        INSERT INTO libraryiq.history(key, last_run) VALUES(?, now())
      };
      $dbh->do($sql_ins, undef, $c->{libraryname});
    }
    $log->("Updated last_run time for key=$c->{libraryname}");
}

# ----------------------------------------------------------
# process_data_type - Process data type and write to file
# ----------------------------------------------------------
sub process_data_type {
    my ($type, $id_sql, $detail_sql, $columns, $dbh, $date_filter, $chunk_size, $tempdir, $log_file, $debug) = @_;
    my @chunks = chunked_ids($dbh, $id_sql, $date_filter, $chunk_size);
    logmsg("Found ".(scalar @chunks)." $type ID chunks", $log_file, $debug);

    my $out_file = File::Spec->catfile($tempdir, "$type.tsv");
    open my $OUT, '>', $out_file or die "Cannot open $out_file: $!";
    print $OUT join("\t", @$columns)."\n";

    foreach my $chunk (@chunks) {
        my @rows = fetch_data_by_ids($dbh, $chunk, $detail_sql);
        foreach my $r (@rows) {
            print $OUT join("\t", map { $_ // '' } @$r), "\n";
        }
    }
    close $OUT;
    logmsg("Wrote $type data to $out_file", $log_file, $debug);
    return $out_file;
}

# ----------------------------------------------------------
# dedupe_array - Remove duplicates from an array
# ----------------------------------------------------------
sub dedupe_array {
    my ($arrRef) = @_;
    my @arr     = $arrRef ? @{$arrRef} : ();
    my %deduper = ();
    $deduper{$_} = 1 foreach (@arr);
    my @ret = ();
    while ( ( my $key, my $val ) = each(%deduper) ) {
        push( @ret, $key );
    }
    @ret = sort @ret;
    return \@ret;
}

# ----------------------------------------------------------
# create_tar_gz - Create a tar.gz archive of the given files
# ----------------------------------------------------------
sub create_tar_gz {
    my ($files_ref, $archive_dir, $filenameprefix, $log_file, $debug) = @_;
    my @files = @$files_ref;
    my $dt = DateTime->now( time_zone => "local" );
    my $fdate = $dt->ymd;
    my $tar_file = File::Spec->catfile($archive_dir, "$filenameprefix" . "_$fdate.tar.gz");

    my $tar = Archive::Tar->new;
    $tar->add_files(@files);
    $tar->write($tar_file, COMPRESS_GZIP);

    logmsg("Created tar.gz archive $tar_file", $log_file, $debug);
    return $tar_file;
}

1;