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
foreach my $file (@files){
	open FILE, $file || die("Could not open file...");
    push @rawdata, $_ while (<FILE>);
    close FILE;             
 }

my @greyraw = grep /postgrey/ ,  @rawdata;
my @greylist = grep {!/cleaning\s/} grep {!/Process\s/} grep {!/starting!\s/} grep {!/Binding\s/} grep {!/whitelisted:\s/} grep {!/postfix.smtp/} grep {!/Setting/} @greyraw;


my $y = strftime "%Y", localtime;
my $year;
my $lastyear = $y -1;
my $month_dato = strftime "%m", localtime;
if ($month_dato =~ /^0/) {
	$month_dato =~ s/^0+//;
}
 
 my @out=();
 foreach $_ ( @greylist ) {
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
			
		my $parser = DateTime::Format::Strptime->new( pattern => '%b %d %Y %H:%M:%S');
        my $dt = $parser->parse_datetime( $date );
        my $dateformat = $dt->ymd("-");
        my $timeformat = $dt->hms;
        my $clientname = $1 if /client_name=(.+?(?=,))/;
        my $clientaddress = $1 if /client_address=(.+?(?=,))/;
		my $action = $1 if /action=(\S+),/;
		my $reason = $1 if /reason=(.+?(?=,))/;
		my $sender = $1 if /sender=(\S+),/;
		if (!defined($sender)){
		$sender = '**NoSenderAddress**DeliveryStatusNotification?**';
        }
        my $senderl = lc ( $sender );
		my $recipient = $1 if /recipient=(\S+)/;
		my $recipientl = lc ( $recipient );
		
		push @out, {
			IsoDate =>$dt,
        	Date=>$dateformat, 
        	Time=>$timeformat,
        	ClientName=>$clientname,
        	ClientAddress=>$clientaddress,
        	Action=>$action,
        	Reason=>$reason,
        	Sender=>$senderl,
        	Recipient=>$recipientl,
		}
 }    
 
 my $mongoclient = MongoDB::MongoClient->new(
    host => "mongodb://192.168.50.15:27017",
    username => "username",
    password => "password",  
);

my $year_dato = strftime "%Y", localtime;
my $month_dato = strftime "%m", localtime;
my $month_year = "$year_dato-$month_dato";
my $collection = "postfix-greylisted-$month_year";
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
	    ClientName => $ref->{'ClientName'},
	    ClientAddress => $ref->{'ClientAddress'},
	    Sender => $ref->{'Sender'},
	    Recipient => $ref->{'Recipient'},
	    Action => $ref->{'Action'},
	    Reason => $ref->{'Reason'},
    	});
	} else {
	if ($date > $latest){
		print "Ongoing,.....","\n";
		$collect->insert( {
		IsoDate => $ref->{'IsoDate'},
	   	Date => $ref->{'Date'}, 
	    Time => $ref->{'Time'},
	    ClientName => $ref->{'ClientName'},
	    ClientAddress => $ref->{'ClientAddress'},
	    Sender => $ref->{'Sender'},
	    Recipient => $ref->{'Recipient'},
	    Action => $ref->{'Action'},
	    Reason => $ref->{'Reason'},
    });
    }
  }
}
 
