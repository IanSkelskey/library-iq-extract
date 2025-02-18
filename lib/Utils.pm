package Utils;

use strict;
use warnings;
use Exporter 'import';
use File::Spec;
use DB qw(chunked_ids fetch_data_by_ids);
use Logging qw(logmsg);
use Archive::Tar;

our @EXPORT_OK = qw(read_config get_last_run_time set_last_run_time process_data_type get_db_config get_org_units create_tar_gz create_history_table check_config check_cmd_args);

# ----------------------------------------------------------
# read_config - Read configuration file
# ----------------------------------------------------------
sub read_config {
    my ($file) = @_;
    open my $fh, '<', $file or die "Cannot open config $file: $!";
    my %c;
    while(<$fh>) {
        chomp;
        s/\r//;
        next if /^\s*#/;     # skip comments
        next unless /\S/;    # skip blank lines
        my ($k,$v) = split(/=/,$_,2);
        $c{$k} = $v if defined $k and defined $v;
    }
    close $fh;
    print "Configuration read from $file:\n";
    foreach my $key (keys %c) {
        print "$key = $c{$key}\n";
    }
    return \%c;
}

# ----------------------------------------------------------
# check_config - Check configuration values
# ----------------------------------------------------------
sub check_config {
    my ($conf) = @_;

    my @reqs = (
        "logfile", "tempdir", "libraryname", "ftplogin",
        "ftppass", "ftphost", "remote_directory", "emailsubjectline",
        "archive", "transfermethod"
    );

    my @missing = ();
    
    for my $i ( 0 .. $#reqs ) {
        # print each one:
        print "Required config: $reqs[$i]\n";
        print "Config value: " . (defined $conf->{ $reqs[$i] } ? $conf->{ $reqs[$i] } : 'undefined') . "\n";
        push( @missing, $reqs[$i] ) if ( !$conf->{ $reqs[$i] } );
    }

    if ( $#missing > -1 ) {
        die "Please specify the required configuration options:\n" . join("\n", @missing) . "\n";
    }
    if ( !-e $conf->{"tempdir"} ) {
        die "Temp folder: " . $conf->{"tempdir"} . " does not exist.\n";
    }

    if ( !-e $conf->{"archive"} ) {
        die "Archive folder: " . $conf->{"archive"} . " does not exist.\n";
    }

    if ( lc $conf->{"transfermethod"} ne 'sftp' ) {
        die "Transfer method: " . $conf->{"transfermethod"} . " is not supported\n";
    }
}

# ----------------------------------------------------------
# check_cmd_args - Check command line arguments
# ----------------------------------------------------------
sub check_cmd_args {
    my ($config_file) = @_;

    if ( !-e $config_file ) {
        die "$config_file does not exist. Please provide a path to your configuration file: --config\n";
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
# get_db_config - Get database configuration from Evergreen config file
# ----------------------------------------------------------
sub get_db_config {
    my ($evergreen_config_file) = @_;
    my $xml = XML::Simple->new;
    my $data = $xml->XMLin($evergreen_config_file);
    return {
        db   => $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{db},
        host => $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{host},
        port => $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{port},
        user => $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{user},
        pass => $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{pw},
    };
}

# ----------------------------------------------------------
# get_org_units - Get organization units based on library shortnames
# ----------------------------------------------------------
sub get_org_units {
    my ($dbh, $libraryname, $include_descendants, $log) = @_;
    my @ret = ();

    # spaces don't belong here
    $libraryname =~ s/\s//g;

    my @sp = split( /,/, $libraryname );

    my $libs = join( '$$,$$', @sp );
    $libs = '$$' . $libs . '$$';

    my $query = "
    select id
    from
    actor.org_unit
    where lower(shortname) in ($libs)
    order by 1";
    $log->($query) if $log;
    my $sth = $dbh->prepare($query);
    $sth->execute();
    while (my @row = $sth->fetchrow_array) {
        push( @ret, $row[0] );
        if ($include_descendants) {
            my @des = @{ get_org_descendants($dbh, $row[0], $log) };
            push( @ret, @des );
        }
    }
    return dedupe_array(\@ret);
}

# ----------------------------------------------------------
# get_org_descendants - Get organization unit descendants
# ----------------------------------------------------------
sub get_org_descendants {
    my ($dbh, $thisOrg, $log) = @_;
    my $query   = "select id from actor.org_unit_descendants($thisOrg)";
    my @ret     = ();
    $log->($query) if $log;

    my $sth = $dbh->prepare($query);
    $sth->execute();
    while (my $row = $sth->fetchrow_array) {
        push( @ret, $row );
    }

    return \@ret;
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

# ----------------------------------------------------------
# create_history_table - Create the libraryiq.history table if it doesn't exist
# ----------------------------------------------------------
sub create_history_table {
    my ($dbh, $log_file, $debug) = @_;
    my $sql = q{
        CREATE SCHEMA IF NOT EXISTS libraryiq;
        CREATE TABLE IF NOT EXISTS libraryiq.history (
            id serial PRIMARY KEY,
            key TEXT NOT NULL,
            last_run TIMESTAMP WITH TIME ZONE DEFAULT '1000-01-01'::TIMESTAMPTZ
        )
    };
    $dbh->do($sql);
    logmsg("Ensured libraryiq.history table exists", $log_file, $debug);
}

1;