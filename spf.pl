#use strict;
#use warnings;
use Date::Parse;
use Data::Dumper;
use DateTime::Format::Strptime;
use POSIX qw(strftime);
use Text::Table;
use Getopt::Long;
use Term::ProgressBar;
use Time::Progress;
use MongoDB;
use Time::Piece;
use IO::Uncompress::Gunzip ();
use Compress::Zlib;
use DateTime;
use BSON::Types ':all';
use MongoDB::BSON;
$MongoDB::BSON::looks_like_number = 1;
use open qw(:std :utf8);
use Encode qw(decode);

my @files = glob("/var/log/mail.info /var/log/mail.info.1");
#print Dumper @files;
foreach my $file (@files){
	open FILE, $file || die("Could not open file...");
    push @rawdata, $_ while (<FILE>);
    close FILE;             
 }

my @spf = grep /policyd-spf/ , @rawdata;
my @spffiltered = grep {!/warning:\s/} @spf;
my @smtp_out=();

print Dumper @spffiltered;

my $y = strftime "%Y", localtime;
my $year;
my $lastyear = $y -1;
my $month_dato = strftime "%m", localtime;
if ($month_dato =~ /^0/) {
	$month_dato =~ s/^0+//;
}

my @out=();
foreach $_ ( @spffiltered ) {
		my $date = substr $_, 0, 15;
		my $t = Time::Piece->strptime($date, "%b %d %H:%M:%S");
		my $month_log = $t->strftime("%m");
		if ($month_log =~ /^0/) {
		$month_log =~ s/^0+//;
		}
		if ($month_log > $month_dato) {
			$year = "$lastyear ";
		} else { 
			$year = "$y ";
		}    
		substr($date, 7, 0) = $year;
		my $spfresult = $1 if /Received-SPF:\s(\S+)\s/;
		my $spfidentity = $1 if /identity=(.+?);/;
		my $clientip = $1 if /client-ip=(\S+);/;
		my $helo = $1 if /helo=(\S+);/;
		my $envelope_from = $1 if /envelope-from=(\S+);/;
        my $parser = DateTime::Format::Strptime->new( pattern => '%b %d %Y %H:%M:%S');
        my $dt = $parser->parse_datetime( $date );
        my $dateformat = $dt->ymd("-");
        my $timeformat = $dt->hms;
        push @out, {
        	IsoDate =>$dt,
        	Date=>$dateformat, 
        	Time=>$timeformat,
			SPFResult=>$spfresult,
			SPFIdentity=>$spfidentity,
			ClientIP=>$clientip,
			Helo=>$helo,
			EnvelopeFrom=>$envelope_from,
        };
 }

my $mongoclient = MongoDB::MongoClient->new(
    host => "mongodb://192.168.50.15:27017",
    username => "username",
    password => "password",  
);	

my $year_dato = strftime "%Y", localtime;
my $month_dato = strftime "%m", localtime;
my $month_year = "$year_dato-$month_dato";
my $collection = "postfix-spf-$month_year";
my $db = $mongoclient->get_database('postfix_dev');
my $collect = $db->get_collection($collection);
my $data = $collect->find({})->sort({IsoDate => -1})->limit(1);

sub latest {
while (my $doc = $data->next) {
	my $parser = DateTime::Format::Strptime->new( pattern => '%y-%m-%dT%H:%M:%S' , time_zone => 'Europe/Berlin', locale => 'de_DE' );
    my $dt = $parser->parse_datetime( $doc->{'IsoDate'} );
    $dt->set_time_zone("local");
    my $last = str2time($dt);
    return $last;
 }
}
my $latest = latest();

for my $ref (@out) {
	my $parser = DateTime::Format::Strptime->new( pattern => '%y-%m-%dT%H:%M:%S' , time_zone => 'Europe/Berlin', locale => 'de_DE' );
	my $dt = $parser->parse_datetime( $ref->{'IsoDate'} );
	$dt->set_time_zone("local");
	my $date = str2time($dt);
	if (!defined $latest){
		print "Initial,.....","\n";
		$collect->insert( {
    	IsoDate => $ref->{'IsoDate'},
	   	Date => $ref->{'Date'}, 
	    Time => $ref->{'Time'},
	    SPFResult => $ref->{'SPFResult'},
		SPFIdentity => $ref->{'SPFIdentity'},
		ClientIP => $ref->{'ClientIP'},
		Helo => $ref->{'Helo'},
		EnvelopeFrom => $ref->{'EnvelopeFrom'},
    	});
	} else {
	if ($date > $latest){
		print "Ongoing,.....","\n";
		$collect->insert( {
		IsoDate => $ref->{'IsoDate'},
	   	Date => $ref->{'Date'}, 
	    Time => $ref->{'Time'},
	    SPFResult => $ref->{'SPFResult'},
		SPFIdentity => $ref->{'SPFIdentity'},
		ClientIP => $ref->{'ClientIP'},
		Helo => $ref->{'Helo'},
		EnvelopeFrom => $ref->{'EnvelopeFrom'},
    });
    
	  }
  }
}

