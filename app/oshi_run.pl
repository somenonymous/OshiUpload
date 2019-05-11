#!/usr/bin/perl
# app loader, however you can load each module separately as well

use strict;
use warnings;
use feature 'say';
use sigtrap;
use Getopt::Long;
use Time::HiRes;
use Mojo::IOLoop;
require "./functions.pm";


my %modules = (
	'engine' => 'hypnotoad -f webapp.pl',
	'tcp' => 'perl tcp.pl',
	'put' => 'perl http_put.pl'
);

my $hypnostop = 'hypnotoad -s webapp.pl && sleep 5';

my %pids;
my ($restart, $stop, $optpid);
GetOptions ("restart"  => \$restart, "stop"  => \$stop, "pid=i" => \$optpid)
  or die("Error in command line arguments\n");


if ( defined $restart ) {
	my $pid = `pgrep -af $0 | grep -v '/bin/sh' | grep -v restart`;
	 if ( $optpid ) {
		kill 'USR1', $optpid;
		say "Sent USR1 to $optpid";
	}elsif ( $pid =~ /^(\d+)/ ) {
		kill 'USR1', $1;
		say "Sent USR1 to $1";
	}else {
		die("Can't find a running PID, you may specify pid with --pid option\n");
	}
	exit;
}elsif ( defined $stop ) {
	my $pid = `pgrep -af $0 | grep -v '/bin/sh' | grep -v stop`;
	 if ( $optpid ) {
		kill 'SIGINT', $optpid;
		say "Sent SIGINT to $optpid";
	}elsif ( $pid =~ /^(\d+)/ ) {
		kill 'SIGINT', $1;
		say "Sent SIGINT to $1";
	}else {
		die("Can't find a running PID, you may specify pid with --pid option\n");
	}
	exit;
}


my %signals;
sub handleSigs {
    my $signalReceived = shift;

    if ($signalReceived eq "INT") { 
		
		foreach (keys %pids) {
			kill 'SIGTERM', $pids{$_};
		}
		exit;
		
	}
    elsif ($signalReceived eq "USR1") { $signals{restart} = 1 }
    #elsif ($signalReceived eq "USR2") { }
    

}
$SIG{INT}=\&handleSigs;
  
$SIG{USR1}=\&handleSigs;


my $main = OshiUpload->new->db_init;

Mojo::IOLoop->recurring(30 => sub {
	my $loop = shift;
	$loop->subprocess(
	  sub {
	    my $subprocess = shift;
	    $main->files_purge_expired;
	    return;
	  },
	  sub {}
	);
});

Mojo::IOLoop->recurring(30 => sub {
	my $loop = shift;
	$loop->subprocess(
	  sub {
	    my $subprocess = shift;
	    $main->captcha_purge_expired;
	    return;
	  },
	  sub {}
	);
});

Mojo::IOLoop->recurring(600 => sub {
	my $loop = shift;
	$loop->subprocess(
	  sub {
	    my $subprocess = shift;
	    $main->files_antivirus_scan();
	    return;
	  },
	  sub {}
	);
});

system ( $hypnostop );

try2run();

Mojo::IOLoop->recurring(10 => sub {
	try2run();
});

sub try2run {

	foreach (keys %pids) {
		delete $pids{$_} unless kill (0, $pids{$_}) 
	}
	
	foreach my $m (keys %modules) {
		unless ( exists $pids{$m} ) {
				my $cmd = $modules{$m};
				my $pid = fork();
				next "unable to fork: $!" unless defined($pid);
				if (!$pid) {  # child
				    exec($cmd);
				    die "unable to exec: $!";
				}
				$pids{$m} = $pid;
		}
	}
	
	if ( exists $signals{restart} ) {
		delete $signals{restart};
		foreach (keys %pids) {
			kill 'SIGTERM', $pids{$_};
		}
	}
	
}


Mojo::IOLoop->start unless Mojo::IOLoop->is_running; 
