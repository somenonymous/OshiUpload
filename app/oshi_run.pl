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
	# 'put' => 'perl http_put.pl' # uncomment to use old standalone server for PUT (curl -T) uploads
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

my %running_files_purge_expired;
Mojo::IOLoop->recurring(30 => sub {
	my $loop = shift;

	if ( keys %running_files_purge_expired >= 1 ) {
		say "Can't launch files_purge_expired() because there are previous unfinished jobs";
		return;
	}
	
	my $subprocess = $loop->subprocess(
	  sub {
	    my $subprocess = shift;
	    $main->files_purge_expired(500);
	    return;
	  },
	  sub {
		my $subprocess = shift;
		delete $running_files_purge_expired{$subprocess->pid} if exists $running_files_purge_expired{$subprocess->pid};
	  }
	);
	
	$subprocess->on(spawn => sub {
	  my $subprocess = shift;
      $running_files_purge_expired{$subprocess->pid} = 1;
	});

});

Mojo::IOLoop->recurring(172800 => sub {
	my $loop = shift;
	$loop->subprocess(
	  sub {
	    my $subprocess = shift;
	    $main->files_purge_untracked;
	    return;
	  },
	  sub {}
	);
});

Mojo::IOLoop->recurring(604800 => sub {
	my $loop = shift;
	$loop->subprocess(
	  sub {
	    my $subprocess = shift;
		$main->files_purge_inexistent();
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
	return unless $main->{conf}->{CLAMAV_SCANS_ENABLED};
	$loop->subprocess(
	  sub {
	    my $subprocess = shift;
	    $main->files_antivirus_scan();
	    return;
	  },
	  sub {}
	);
});

Mojo::IOLoop->recurring(60 => sub {
	my $loop = shift;
	$loop->subprocess(
	  sub {
	    my $subprocess = shift;
	    $main->process_unfinished_hashsum();
	    return;
	  },
	  sub {my ($subprocess, $err) = @_; say $err if $err}
	);
});

Mojo::IOLoop->recurring($main->{conf}->{UPLOAD_AUTOREMOVE_ON_ABUSE_INTERVAL} => sub {
	return unless $main->{conf}->{UPLOAD_AUTOREMOVE_ON_ABUSE};
	my $loop = shift;
	$loop->subprocess(
	  sub {
	    my $subprocess = shift;
	    
			
			my $rows;
			$main->{dbc}->run(sub {
				$rows = $_->selectall_arrayref('select * from reports order by time', { Slice => {} } );
			});
		
			foreach my $record (@{$rows}) {
		
				$main->{dbc}->run(sub {
					if ($main->{conf}->{UPLOAD_AUTOREMOVE_ON_ABUSE_BEHAVIOR} eq 'remove') {
						$_->do('delete from uploads where urlpath = ?', undef, $record->{url});
					} else {
						$_->do('update uploads set oniononly = 1, oniononlylocked = 1 where urlpath = ?', undef, $record->{url});
					}
				});
		
			}
	
	    return;
	  },
	  sub {}
	);
});

if ( $main->{conf}->{MODULES_AUTOSTART} ) {
 system ( $hypnostop );

 try2run();

 Mojo::IOLoop->recurring(10 => sub {
	try2run();
 });
}

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
