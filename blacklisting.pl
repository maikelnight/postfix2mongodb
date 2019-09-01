#use strict;
#use warnings;
use Data::Dumper;
use Date::Parse;
use DateTime::Format::Strptime;
use POSIX qw(strftime);
use Text::Table;
use Getopt::Long;
use Term::ProgressBar;
use Time::Progress;
#use Text::SimpleTable::AutoWidth;
use MongoDB;
use Time::Piece;
use IO::Uncompress::Gunzip ();
use Compress::Zlib;

my @files = glob("/var/log/mail.info /var/log/mail.info.1");
print Dumper @files;
foreach my $file (@files){
	open FILE, $file || die("Could not open file...");
    push @rawdata, $_ while (<FILE>);
    close FILE;             
 }
  
#print Dumper @rawdata;
my @blacklist = grep /blocked/ ,  @rawdata;
#print Dumper @blacklist;
 
my $y = strftime "%Y", localtime;
my $year;
my $lastyear = $y -1;
my $month_dato = strftime "%m", localtime;
if ($month_dato =~ /^0/) {
	$month_dato =~ s/^0+//;
}

my @out=();
 foreach $_ ( @blacklist ) {
		my $date = substr $_, 0, 15;
		#print $date, "\n";
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
			
		my $parser = DateTime::Format::Strptime->new( pattern => '%b %d %Y %H:%M:%S');
        my $dt = $parser->parse_datetime( $date );
        my $dateformat = $dt->ymd("-");
        my $timeformat = $dt->hms;
		
		my $server = $1 if /from\s(\S+)[[]/;
		my $ip = $1 if /$server[[](\S+)[]]:/;
		my $list = $1 if /using\s(\S+);/;
		my $sender = $1 if /from=<(\S+)>/;
		my $recipient = $1 if /to=<(\S+)>/;
		
		push @out, {
			IsoDate =>$dt,
        	Date=>$dateformat, 
        	Time=>$timeformat,
        	Server=>$server,
        	Ip=>$ip,
        	Blacklist=>$list,
        	Sender=>$sender,
        	Recipient=>$recipient,
		}
 }
 
 my $mongoclient = MongoDB::MongoClient->new(
    host => "mongodb://192.168.50.15:27017",
    username => "user",
    password => "password",  
);

my $year_dato = strftime "%Y", localtime;
my $month_dato = strftime "%m", localtime;
my $month_year = "$year_dato-$month_dato";
my $collection = "postfix-blacklisted-$month_year";
my $db = $mongoclient->get_database('postfix_dev');
my $collect = $db->get_collection($collection);
my $data = $collect->find({})->sort({IsoDate => -1})->limit(1);

sub latest {
while (my $doc = $data->next) {
	my $parser = DateTime::Format::Strptime->new( pattern => '%y-%m-%dT%H:%M:%S' , time_zone => 'Europe/Berlin', locale => 'de_DE' );
    my $dt = $parser->parse_datetime( $doc->{'IsoDate'} );
    $dt->set_time_zone("local");
    #print $dt, "\n";
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
	#print $dt, "\n";
	if (!defined $latest){
		print "Initial,.....","\n";
		$collect->insert( {
    	IsoDate => $ref->{'IsoDate'},
	   	Date => $ref->{'Date'}, 
	    Time => $ref->{'Time'},
	    Sender => $ref->{'Sender'},
	    Recipient => $ref->{'Recipient'},
	    Blacklist => $ref->{'Blacklist'},
	    IP => $ref->{'Ip'},
    	});
	} else {
	if ($date > $latest){
		print "Ongoing,.....","\n";
		$collect->insert( {
		IsoDate => $ref->{'IsoDate'},
	   	Date => $ref->{'Date'}, 
	    Time => $ref->{'Time'},
	    Sender => $ref->{'Sender'},
	    Recipient => $ref->{'Recipient'},
	    Blacklist => $ref->{'Blacklist'},
	    IP => $ref->{'Ip'},    	
    });
	}
    #print "added", " ", $ref->{'EmailID'}, "\n"; 
  }
}

 
