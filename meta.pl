use strict;
use warnings;
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
use Parallel::ForkManager;

my $initial = '';
GetOptions(
	'initial' => \$initial,
	);

my @files = ();
my @rawdata = ();

my $max_processes = 10;
#my $pm = new Parallel::ForkManager($max_processes);
my $pm = Parallel::ForkManager->new($max_processes);

if ($initial eq '1'){
	@files = glob("/var/log/mail.info.*.gz");
	foreach my $file (@files){
	my $gz = gzopen($file, "rb") or die "Cannot open $file: $gzerrno\n" ;
	while ($gz->gzreadline($_) > 0) {
    chomp;
    push @rawdata, $_;
 			}
		}
	} else {
    @files = glob("/var/log/mail.info /var/log/mail.info.1");	
	foreach my $file (@files){
	open FILE, $file || die("Could not open file...");
    push @rawdata, $_ while (<FILE>);
    close FILE;             
 	}
}

my @rawstuff = grep /smtpd/ , grep /]:\s([a-z0-9].*):\scl/ , @rawdata;

my @emailids;
foreach my $val ( @rawstuff ){		 
         my ( $emailid ) = ( $val =~ m/]:\s([a-z0-9].*):\scl/ );
         	push @emailids, $emailid unless grep{$_ eq $emailid} @emailids;
   }

my @filtered = ();
my @from = ();
my @cleanup = (); 

for my $id (@emailids){
	push @filtered, grep /smtp\[.*]:\s[0-9]/ , grep /$id/ , @rawdata ;
	push @from, grep /qmgr/ , grep /from=<(\S+)>/ , grep /$id/ , @rawdata ;
	push @cleanup , grep /cleanup/ , grep /$id/ , grep /info:/ , @rawdata ;
}

my @metadata = ();
foreach my $val ( @filtered ){
		my $y = strftime "%Y", localtime;
		my $year;
		my $lastyear = $y -1;
		my $month_dato = strftime "%m", localtime;
		if ($month_dato =~ /^0/) {
			$month_dato =~ s/^0+//;
		}
			
		my $date = substr $val, 0, 15;
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
        my ( $statusinfo ) = ( $val =~ m/([(](?!queue\sactive).*[)])/ );
			if (!defined($statusinfo)){
				($statusinfo) = ( $val =~ m/$emailid:\s(.*)/ );
		}
		if ( $statusinfo =~ m/[(]in reply to RCPT TO command[)]/ ) {
        		($statusinfo) = ( '***CheckDSN***' );
        	}
		my ( $recipient ) = ( $val =~ m/to=<(\S+)>/ );
		if (!defined($recipient)){
         		($recipient) = ( '***RecipientNotYetGrepable-CheckDSN***' );
         }
		my $recipientl = lc ( $recipient );

        push @metadata, {
         	EmailID=>$emailid,
         	DSN=>$dsn,
         	Status=>$status,
         	StatusInfo=>$statusinfo,
         	Recipient=>$recipientl,
         	IsoDate =>$dt,
        	Date=>$dateformat, 
        	Time=>$timeformat ,
         }
}

my @from_ = ();
foreach my $from (@from) {
	my ( $emailid ) = ( $from =~ m/]:\s(\S+):/ );
	my ($sender) = ( $from =~ m/from=<(\S+)>/);
	if (!defined($sender)){
		$sender = '**NoSenderAddress**DeliveryStatusNotification?**';
        }
        my $senderl = lc ( $sender );
        push @from_, {
        	EmailID=>$emailid,
        	Sender=>$sender,
        }
}

my @subject = ();
foreach my $subject (@cleanup) {
	my ( $emailid ) = ( $subject =~ m/]:\s(\S+):/ );
	my ($subject_) = ( $subject =~ m/Subject:(.*)\sfrom\s/);
	
	eval { $subject_ = decode("MIME-Header", $subject_) };
       	if ($@){print "Fehler in der Kodierung $subject", "\n"} else {
        	$subject_ = decode("MIME-Header", $subject_);
       	}
	
        push @subject, {
        	EmailID=>$emailid,
        	Info=>$subject_,
        }
}

my %subj_hash = map { $_->{'EmailID'} => $_->{'Info'}  } @subject;

my @results = ();
for my $ref1 (@metadata){
	my $id1 = $ref1->{'EmailID'};
	
		my $info;
			if(!exists($subj_hash{$id1})) { 
			 $info = " ";
			} else {
				$info = $subj_hash{$id1};
			}
			#print $id1, " ", $info, "\n";
			
		for my $ref2 (@from_){
			my $id2 = $ref2->{'EmailID'};
				
		if ( ($id1 eq $id2) ){
			push @results, {
				EmailID=>$id1,
				IsoDate=>$ref1->{'IsoDate'},
				Date=>$ref1->{'Date'},
				Time=>$ref1->{'Time'},
				Sender=>$ref2->{'Sender'},
				Recipient=>$ref1->{'Recipient'},
				Info=>$info,
				DSN=>$ref1->{'DSN'},
				Status=>$ref1->{'Status'},
				StatusInfo=>$ref1->{'StatusInfo'},
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
my $collection = "postfix-results-$month_year";
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
    	});
	} else {
	if ($date > $latest){
		print "Ongoing,.....(newest document $dt)","\n";
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
    });
	}
  }
}

exit;
