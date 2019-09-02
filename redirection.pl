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

my @send_receive = grep /cleanup/ , grep /from/ ,  @rawdata;
my @smtp = grep /smtp\[.*]:\s[0-9]/ , @rawdata;
#my @postgrey = grep /postgrey/ , grep /action/ , @rawdata;
#my @umleitungen = grep /orig_to/ , @rawdata;
my @smtp_out=();

#print Dumper @smtp;

foreach my $val ( @smtp ){
	
		my ( $orig_to ) = ( $val =~ m/orig_to=<(\S+)>,/ );
          	if (!defined($orig_to)){
				#($orig_to) = ( '***keine Umleitung***' );
				next;	
          }

		  #print Dumper $orig_to;
          
         my ( $recipientSMTP ) = ( $val =~ m/to=<(\S+)>,/ );
         my $recipientlSMTP = lc ( $recipientSMTP ); 

		 print Dumper $recipientlSMTP;
	
         my ( $emailid ) = ( $val =~ m/]:\s(\S+):/ );
          
         my ( $dsn ) = ( $val =~ m/dsn=(\S+),/ );
         	if (!defined($dsn)){
				($dsn) = ( $val =~ m/said:\s(.*)/ );	
          }
          	if (!defined($dsn)){
				($dsn) = ( '***DSNNotDefined***' );	
          }
         my ( $status ) = ( $val =~ m/status=(\S+)/ );
         	if (!defined($status)){
         		($status) = ( '***StatusNotDefinedYet***' );
         }
         my ( $statusinfo ) = ( $val =~ m/([(].*[)])/ );
         	if (!defined($statusinfo)){
         		($statusinfo) = ( $val =~ m/$emailid:\s(.*)/ );
         }
         push @smtp_out, {
         	EmailID=>$emailid,
         	DSN=>$dsn,
         	Status=>$status,
         	StatusInfo=>$statusinfo,
         	Origin=>$orig_to,
         	Weiterleitung=>$recipientlSMTP,
         }
    }
    
my $y = strftime "%Y", localtime;
my $year;
my $lastyear = $y -1;
my $month_dato = strftime "%m", localtime;
if ($month_dato =~ /^0/) {
	$month_dato =~ s/^0+//;
}

my @out=();
foreach $_ ( @send_receive ) {
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
		my $id = $1 if /]:\s(\S+):/;
        my $recipient = $1 if /to=<(\S+)>/;
        my $recipientl = lc ( $recipient );
        my $sender = $1 if /from=<(\S+)>/;
		if (!defined($sender)){
		$sender = '**NoSenderAddress**DeliveryStatusNotification?**';
        }
        my $senderl = lc ( $sender );
        my $info = $1 if /Subject:(.*)\sfrom\s/;
        my $parser = DateTime::Format::Strptime->new( pattern => '%b %d %Y %H:%M:%S');
        my $dt = $parser->parse_datetime( $date );
        my $dateformat = $dt->ymd("-");
        my $timeformat = $dt->hms;
        push @out, {
        	IsoDate =>$dt,
        	Date=>$dateformat, 
        	Time=>$timeformat ,
        	Sender=>$senderl,
        	EmailID=>$id, 
        	Recipient=>$recipientl,
        	Info=>$info
        };
 }
 
 my @results = ();
for my $ref1 (@out){
	my $id1 = $ref1->{'EmailID'};
		for my $ref2 (@smtp_out){
			my $id2 = $ref2->{'EmailID'};
		if ($id1 eq $id2){
			push @results, {
				EmailID=>$id1,
				IsoDate=>$ref1->{'IsoDate'},
				Date=>$ref1->{'Date'},
				Time=>$ref1->{'Time'},
				Sender=>$ref1->{'Sender'},
				Recipient=>$ref1->{'Recipient'},
				Info=>$ref1->{'Info'},
				DSN=>$ref2->{'DSN'},
				Status=>$ref2->{'Status'},
				StatusInfo=>$ref2->{'StatusInfo'},
				Weiterleitung=>$ref2->{'Weiterleitung'},
			} 
		}
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
my $collection = "postfix-redirection-$month_year";
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

for my $ref (@results) {
	my $parser = DateTime::Format::Strptime->new( pattern => '%y-%m-%dT%H:%M:%S' , time_zone => 'Europe/Berlin', locale => 'de_DE' );
	my $dt = $parser->parse_datetime( $ref->{'IsoDate'} );
	$dt->set_time_zone("local");
	my $date = str2time($dt);
	#print $dt, "\n";
	if (!defined $latest){
		print "Initial,.....","\n";
		$collect->insert( {
    	EmailID => $ref->{'EmailID'},
    	IsoDate => $ref->{'IsoDate'},
	   	Date => $ref->{'Date'}, 
	    Time => $ref->{'Time'},
	    Sender => $ref->{'Sender'},
	    Recipient => $ref->{'Recipient'},
	    Info => $ref->{'Info'},
	    DSN => $ref->{'DSN'},
	    Status => $ref->{'Status'},
	    StatusInfo => $ref->{'StatusInfo'},
	    Weiterleitung=>$ref->{'Weiterleitung'},
    	});
	} else {
	if ($date > $latest){
		print "Ongoing,.....(neustes Dokument $dt)","\n";
		$collect->insert( {
    	EmailID => $ref->{'EmailID'},
    	IsoDate => $ref->{'IsoDate'},
	   	Date => $ref->{'Date'}, 
	    Time => $ref->{'Time'},
	    Sender => $ref->{'Sender'},
	    Recipient => $ref->{'Recipient'},
	    Info => $ref->{'Info'},
	    DSN => $ref->{'DSN'},
	    Status => $ref->{'Status'},
	    StatusInfo => $ref->{'StatusInfo'},
	    Weiterleitung=>$ref->{'Weiterleitung'},
    });
	}
  }
}

exit;
