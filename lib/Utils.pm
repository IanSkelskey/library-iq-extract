package Utils;

use strict;
use warnings;
use Exporter 'import';
use Encode;
use File::Spec;
use Logging qw(logmsg);
use Archive::Tar;
use DateTime;
use Getopt::Long;

our @EXPORT_OK = qw(read_config read_cmd_args check_config check_cmd_args create_tar_gz dedupe_array write_data_to_file);

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
    my ($config_file, $evergreen_config_file, $debug, $full, $no_email, $no_sftp, $drop_history) = @_;
    $evergreen_config_file ||= '/openils/conf/opensrf.xml';  # Default value

    GetOptions(
        "config=s"           => \$config_file,
        "evergreen-config=s" => \$evergreen_config_file,
        "debug"              => \$debug,
        "full"               => \$full,
        "no-email"           => \$no_email,
        "no-sftp"            => \$no_sftp,
        "drop-history"       => \$drop_history,
    );

    return ($config_file, $evergreen_config_file, $debug, $full, $no_email, $no_sftp, $drop_history);
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
# write_data_to_file - Write data to a file
# ----------------------------------------------------------
sub write_data_to_file {
    my ($type, $data, $columns, $tempdir) = @_;

    # Define the output file path
    my $out_file = File::Spec->catfile($tempdir, "$type.tsv");

    # Open the output file for writing
    my $error = "Cannot open $out_file: $!";
    open my $OUT, '>', $out_file or do {
        logmsg("ERROR", $error);
        die $error;
    };

    # Write the column headers to the output file
    print $OUT join("\t", @$columns)."\n";

    # Write each row of data to the output file
    foreach my $r (@$data) {
        print $OUT Encode::encode('UTF-8', join("\t", map { $_ // '' } @$r) . "\n");
    }

    # Close the output file
    close $OUT;

    # Log the completion of the data writing process and file size
    my $file_size = -s $out_file;
    logmsg("INFO", "Wrote $type data to $out_file (File size: $file_size bytes)");

    return $out_file;
}

# ----------------------------------------------------------
# create_tar_gz - Create a tar.gz archive of the given files
# ----------------------------------------------------------
sub create_tar_gz {
    my ($files_ref, $archive_dir, $filenameprefix, $full) = @_;
    my @files = @$files_ref;
    my $dt = DateTime->now( time_zone => "local" );
    my $fdate = $dt->ymd;
    my $suffix = $full ? 'full' : 'diff';
    my $tar_file = File::Spec->catfile($archive_dir, "$filenameprefix" . "_$fdate" . "_$suffix.tar.gz");

    my $tar = Archive::Tar->new;
    $tar->add_files(@files);
    $tar->write($tar_file, COMPRESS_GZIP);

    logmsg("INFO", "Created tar.gz archive $tar_file");
    return $tar_file;
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

1;