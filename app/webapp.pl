#!/usr/bin/perl

use Mojolicious::Lite;
use GD::SecurityImage;
use Data::Random qw(:all);
use Try::Tiny;
use JavaScript::Minifier qw(minify);
require "./functions.pm";

my $main = OshiUpload->new;
app->config(hypnotoad => { listen => ['http://' . $main->{conf}->{HTTP_APP_ADDRESS}. ':' . $main->{conf}->{HTTP_APP_PORT}],
						   workers => 8,
						   pid_file => '/tmp/hypnotoad_oshi.pid'
						  });
$main->db_init;

my $FILE_MAX_SIZE = ($main->{conf}->{HTTP_UPLOAD_FILE_MAX_SIZE} || 1000) * 1048576;
my $htmlstuff = {'yes' => 1, 'no' => 0, 'true' => 1, 'false' => 0};

open my $js, '<', 'public/static/bundle.js' or die($!);
my $minjs = minify(input => $js);
close $js;
$minjs =~ s/[\r\n]/ /g;

hook before_dispatch => sub {
    my $c = shift;
    my $downstreamproto = $c->req->url->to_abs->scheme;
	$downstreamproto = $c->req->headers->header('X-Forwarded-Proto') if $c->req->headers->header('X-Forwarded-Proto');
	my $vars = $main->template_vars;
	$vars->{'BASEURL'} = $c->req->url->to_abs->host_port;
	$vars->{'BASEURLPROTO'} = $downstreamproto;
	$c->stash($vars);
};

under $main->{conf}->{ADMIN_ROUTE} => sub {
	my $c = shift;
	
	$c->reply->not_found and return 
		if ( $main->{conf}->{ADMIN_HOST} && lc $c->req->url->to_abs->host ne lc $main->{conf}->{ADMIN_HOST} );
	
	$c->stash(
		file => {},
		ADMIN_ROUTE => $main->{conf}->{ADMIN_ROUTE}
	);
	
	if ($main->admin_auth($c->req->url->to_abs->userinfo)) {
		$main->{dbc}->run(sub {	
			$c->stash( REPORT_COUNT => $_->selectrow_array("select count(*) from reports") )
		});
		return 1;
	}

	$c->res->headers->www_authenticate('Basic');
	$c->render(text => 'Authentication required!', status => 401);
	return undef;
};

get '/' => sub {
	my $c = shift;

	my $url = $c->param('file');
	if ( defined $url ) {
		my $row = $main->get_file('url', $url);
		if ( $row ) {
			$c->stash(file => $row);
			
			my $expire = $c->param('expire');
			if ( $c->param('delete') ) {
				$main->delete_file('mpath', $row->{'mpath'});
				$c->stash(SUCCESS => "The file has been deleted");
			}elsif ( $c->param('toggleautodestroy') ) {
				$row->{'autodestroy'} = !$row->{'autodestroy'};
				$main->{dbc}->run(sub {
					$_->do("update uploads set autodestroy = ? where mpath = ?", undef, $row->{'autodestroy'}, $row->{'mpath'} );
				});
				return $c->redirect_to($c->req->url->path->to_abs_string . '?file=' . $row->{'urlpath'});

			}elsif ( $c->param('toggleautodestroylock') ) {
				$row->{'autodestroylocked'} = !$row->{'autodestroylocked'};
				$main->{dbc}->run(sub {
					$_->do("update uploads set autodestroylocked = ? where mpath = ?", undef, $row->{'autodestroylocked'}, $row->{'mpath'} );
				});
				return $c->redirect_to($c->req->url->path->to_abs_string . '?file=' . $row->{'urlpath'});
				
			}elsif ( defined $expire && int $expire >= 0 ) {
				my @ex = $main->expiry_check($expire, $row->{'expires'});
	
				if ( $expire != 0 && $ex[0] != 1 ) {
					$c->stash(ERROR => $ex[1])
				} else {
					$row->{'expires'} = $expire == 0 ? 0 : (time+($expire*60));
					$main->{dbc}->run(sub {
						$_->do("update uploads set expires = ?", undef, $row->{'expires'} );
					});
					$c->stash(SUCCESS => "The file expiry has been updated");
				}
				
			}
		} else {
			$c->stash(ERROR => 'The file you provided does not exist on our service')
		}
	} else {
		my $df = `df -h $main->{conf}->{UPLOAD_STORAGE_PATH}`;
		$c->stash(STAT_DF => $df);
		
		$main->{dbc}->run(sub {$c->stash(STAT_FILES => $_->selectrow_array('select count(*) from uploads where type = ?', undef, 'file'));});
		$main->{dbc}->run(sub {$c->stash(STAT_LINKS => $_->selectrow_array('select count(*) from uploads where type = ?', undef, 'link'));});
	}
	
	return $c->render(template=>'admin');
};

get '/reports/' => sub {
	my $c = shift;
	
	my $resolved = $c->param('resolved');
	if ( $resolved ) {
		$main->{dbc}->run(sub {
			$_->do('delete from reports where url = ?', undef, $resolved);
		});
		return $c->redirect_to($c->req->url->path->to_abs_string);
	}
	
	my $purgeall = $c->param('purgeall');
	if ( $purgeall ) {
		my  $row = $main->get_file('urlpath', $purgeall);
		my $d;
		$main->{dbc}->run(sub {
			$d = $_->selectall_arrayref('select mpath,type from uploads where hashsum = ? and size = ? order by type desc', { Slice => {} }, $row->{'hashsum'}, $row->{'size'});
		});

		foreach my $record (@{$d}) {
			$main->delete_file('mpath', $record->{'mpath'}, 'fg');
		}

		return $c->redirect_to($c->req->url->path->to_abs_string);
	}
	
	my $d;
	$main->{dbc}->run(sub {
		$d = $_->selectall_arrayref('select * from reports order by time asc', { Slice => {} } );
	});
	my $reports = [];
	foreach my $record (@{$d}) {
		my  $row = $main->get_file('urlpath', $record->{url});
		$record->{info} = $row;
		$main->{dbc}->run(sub {
			$record->{count} = $_->selectrow_array('select count(*) from uploads where hashsum = ?  and size = ?', undef, $row->{'hashsum'}, $row->{'size'});
		});
		push @{$reports}, $record;
	}
	$c->stash( 'REPORTS' => $reports );
	return $c->render(template=>'admin_reports');
};

under '/';

get '/minified.js' => sub {
	my $c = shift;
	return $c->render(text => $minjs, format => 'javascript');
};

get '/nossl' => sub {
	# just in case someone need to upload/download Firefox in IE on Windows XP
	my $c = shift;
	return $c->render(template => 'mainIE') if $c->req->headers->user_agent =~ /MSIE|Trident/;
	$c->render(template => 'main');
};

get '/' => sub {
	my $c = shift;
	return $c->render(template => 'mainIE') if $c->req->headers->user_agent =~ /MSIE|Trident/;
	$c->render(template => 'main');
};

get '/sharex' => sub {
	my $c = shift;
	
	$c->render(template => 'sharex');
};

get '/cmd' => sub {
	my $c = shift;
	
	$c->render(template => 'cmd');
};

get '/abuse' => sub {
	my $c = shift;
	
	if ( $main->{conf}->{CAPTCHA_SHOW_FOR_ABUSE} ) {
		my $rnd = rand_chars ( set => 'alpha', min => 10, max => 15 );
		$c->stash( captchatoken => $rnd );
	}
	
	$c->render(template => 'abuseform');
};

post '/abuse' => sub {
	my $c = shift;

	if ( $main->{conf}->{CAPTCHA_SHOW_FOR_ABUSE} ) {
		my $rnd = rand_chars ( set => 'alpha', min => 10, max => 15 );
		$c->stash( captchatoken => $rnd );
		my $captchasolved = $main->check_captcha($c->param('captcha'), $c->param('captchatoken'));
	
		return $c->render(template => 'abuseform', ERROR => 'Captcha token is out of date, please try again') if $captchasolved == -1;
		return $c->render(template => 'abuseform', ERROR => 'Captcha is invalid, please try again') if $captchasolved == 0;
	}
	
	my $url = $c->param('url');
	my $urlpath = $url;
	$urlpath =~ s/^[^\/]*https?\:\/\///i;
	$urlpath =~ s/^[^\/]*\///;
	if ( $urlpath =~ /^([a-zA-Z0-9]+)/ ) {
		$urlpath = $1;
	} else {
		return $c->render(template => 'abuseform', ERROR => 'The file you provided does not exist on our service');
	}
	
	my $email = $c->param('email');
	my $comment = $c->param('comment');

	Mojo::IOLoop->subprocess(
		sub {
			my $subprocess = shift;

			my $row = $main->db_get_row('uploads', 'urlpath', $urlpath);
			
			return $row unless $row;
			
			$main->{dbc}->run(sub {
				my $dbh = shift;
				$dbh->do("insert into reports values (?,?,?,?)", undef, time, $urlpath, $email, $comment);
			});
			
			return $row;
		},
		sub {
			my ($subprocess, $err, $row) = @_;
			$c->reply->exception($err) and return if $err;
			return $c->render(template => 'abuseform', ERROR => 'The file you provided does not exist on our service') unless $row;
			return $c->render(template => 'abuseform', SUCCESS => 'The file has been successfully reported')
		}

	);

};

get $main->{conf}->{UPLOAD_MANAGE_ROUTE} . ':fileid' => sub {
	my $c = shift;
	my $mpath = $c->param('fileid');
	my $rnd = rand_chars ( set => 'alpha', min => 10, max => 15 );
	
	my $captchasolved = $main->check_captcha($c->param('captcha'), $c->param('captchatoken'));

	Mojo::IOLoop->subprocess(
		sub {
			my $subprocess = shift;

			$mpath =~ s/[^a-zA-Z0-9]//g;
			my $row = $main->db_get_row('uploads', 'mpath', $mpath);
			
			return $row unless $row;
			return $row if $row->{'processing'};
			
			my $expire = $c->param('expire');
			
			if ( $c->param('delete') ) {
				$main->delete_file('mpath', $mpath);
				return ($row, ['SUCCESS', "The file has been deleted"]);
			}elsif ( $c->param('toggleautodestroy') ) {
				return ($row, ['ERROR', 'This feature was disabled for your file']) if $row->{'autodestroylocked'};
				$row->{'autodestroy'} = !$row->{'autodestroy'};
				$main->{dbc}->run(sub {
					my $dbh = shift;
					$dbh->do("update uploads set autodestroy = ? where mpath = ?", undef, $row->{'autodestroy'}, $mpath );
				});
				return ($row, ['REFRESH', undef]);
			}elsif ( defined $expire && int $expire >= 0 ) {
				my @ex = $main->expiry_check($expire, $row->{'expires'});
	
				if ( $ex[0] != 1 ) {
					return ($row, ['ERROR', $ex[1]]);
				}
				
				return ($row, ['ERROR', 'Captcha token is out of date, please try again']) if $captchasolved == -1;
				return ($row, ['ERROR', 'Captcha is invalid, please try again']) if $captchasolved == 0;
				
				$row->{'expires'} = $expire == 0 ? 0 : (time+($expire*60));
				$main->{dbc}->run(sub {
					my $dbh = shift;
					$dbh->do("update uploads set expires = ?", undef, $row->{'expires'} );
				});
				
				return ($row, ['SUCCESS', "The file expiry has been updated"]);
			}
			
			return $row;
		},
		sub {
			my ($subprocess, $err, $row, $msg) = @_;
			$c->reply->exception($err) and return if $err;
			$c->reply->not_found and return unless $row;
			
			return $c->render(text => "File is finishing processing (calculating hashsum), please retry in some seconds") if $row->{'processing'};

			
			eval { utf8::decode($row->{rpath}) };
			$c->stash( 	file => $row,
						captchatoken => $rnd );
				
			return $c->redirect_to($c->req->url->to_abs->path) if $msg &&  $msg->[0] eq 'REFRESH';
			
			$c->stash( $msg->[0] => $msg->[1] ) if $msg;
			
			
			return $c->render(template => 'manage');

		}
	);

};

get '/captcha/:cid' => sub {
	my $c = shift;
	my $cid = $c->param('cid');
	
	my $image = GD::SecurityImage->new(
	               width   => 80,
	               height  => 30,
	               lines   => 10,
	               gd_font => 'giant',
	            );
	$image->random();
	$image->create( normal => 'rect', [10,10,10], [210,210,50] );
	my($image_data, $mime_type, $random_number) = $image->out;
	$main->captcha_token('add', [ $cid, $random_number ]);
	$c->render(data => $image_data, format => $mime_type);
	
};

hook after_build_tx => sub {
  my $tx = shift;
  # Subscribe to "upgrade" event to identify multipart uploads
  $tx->req->content->on(upgrade => sub {
    my ($single, $multi) = @_;
    return unless $tx->req->url->to_abs->path eq '/' and $tx->req->method eq 'POST';
	$tx->req->max_message_size($FILE_MAX_SIZE);
	if ( $tx->req->headers->content_length > $FILE_MAX_SIZE ) {
		$tx->req->{content_length_is_over_limit} = 1;
		$tx->emit('request');
	}
  });
};

post '/' => sub {
	my $c = shift;
	$c->stash(ERROR => 0);

	my $expire = $c->param('expire');
	my $autodestroy = $c->param('autodestroy');
	my $randomizefn = $c->param('randomizefn');
	my $shorturl = $c->param('shorturl');
	my $nojs = $c->param('nojs');

	if (exists $c->req->{content_length_is_over_limit} || $c->req->is_limit_exceeded ) {
		my $error = "File is too big (max size: " . $main->{conf}->{HTTP_UPLOAD_FILE_MAX_SIZE} . "MB)";
		return $c->render(status => 413, json => { success => 0, error => $error }) if $c->req->is_xhr;
		return $c->render(template => 'main', ERROR => $error, status => 413) if $nojs;
		return $c->render(status => 413, text => $error . "\n");
	}
	

	my @ex = $main->expiry_check($expire) if defined $expire;
	
	if ( defined $expire && $ex[0] != 1 ) {
		return $c->render( json => { success => 0, error =>$ex[1] } ) if $c->req->is_xhr;
		return $c->render( template => 'main', ERROR => $ex[1] ) if $nojs;
		return $c->render( text => $ex[1]. "\n");
	}
	
	$autodestroy = $htmlstuff->{$autodestroy} if exists $htmlstuff->{$autodestroy};
	$randomizefn = $htmlstuff->{$randomizefn} if exists $htmlstuff->{$randomizefn};
	$shorturl = $htmlstuff->{$shorturl} if exists $htmlstuff->{$shorturl};

	my $files = [];
	for my $file (@{$c->req->uploads('files')}) {
		my $size = $file->size;
		my $name = $file->filename;
		my $unparsed_name = $name;
		$name = $main->parse_filename($name);
		my $upstreamfilename = $randomizefn ? $main->newfilename('random', $name) : $name;
		
		my @fncheck = $main->filename_check($upstreamfilename);
		next unless $fncheck[0]; # just skip for now. feel free to improve
	
		my $urlpath = $main->newfilename();
		my $adminpath = $main->newfilename('manage');
		my $filepath =  $main->build_filepath($main->{conf}->{UPLOAD_STORAGE_PATH}, $urlpath, $upstreamfilename);
		
		my $urladdon = $shorturl == 0 ? '/' . $upstreamfilename : '';

		my $baseurl = $main->{conf}->{'UPLOAD_LINK_USE_HOST'} ? join('://', $c->stash('BASEURLPROTO'), $c->stash('BASEURL')) : undef;
		my $p1 = $main->build_url(undef, $urlpath . $urladdon, $baseurl);
		my $p2 = $main->build_url('manage', $adminpath, $baseurl);
		
		try { 
			utf8::decode($p1);
		};

		push @{$files}, {'url' => $p1, 'manageurl' => $p2, 'name' => $unparsed_name};
		$file->move_to($filepath);
		$main->process_file(	
						'http',
						$adminpath,
						$main->{conf}->{UPLOAD_STORAGE_PATH},
						$urlpath, 
						$upstreamfilename, 
						$file->size, 
						$shorturl,
						$expire,
						$autodestroy
					);
	}
	
	$c->stash(FILES => $files);

	return $c->render(template => 'uploadcomplete') if $nojs;

	return $c->render(json => { success => 1, files => $files }) if $c->req->is_xhr;

	return $c->render(text => join("\n", map { join("\n", 'MANAGE: ' . $_->{manageurl}, 'DL: ' . $_->{url}) } @{$files}) . "\n");
	
};

get '/:fileid/*filename' => { filename => undef } => sub {
	my $c = shift;
	my $cfilename = $c->param('filename');
	$cfilename = $main->parse_filename($cfilename) if $cfilename;

	Mojo::IOLoop->subprocess(
		sub {
			my $subprocess = shift;

			my $urlpath = $c->param('fileid');
			$urlpath =~ s/[^a-zA-Z0-9]//g;
			my $row = $main->db_get_row('uploads', 'urlpath', $urlpath);

			$main->{dbc}->run(sub {
				my $dbh = shift;
				$dbh->do("update uploads set hits = hits + 1 where urlpath = ?", undef, $urlpath );
			}); 

			#try { utf8::encode($row->{'rpath'}) };

			return $row;
		},
		sub {
			my ($subprocess, $err, $row) = @_;
			$c->reply->exception($err) and return if $err;
			$c->reply->not_found and return unless $row;
			$c->reply->not_found and return if ( $row->{'shorturl'} == 0 and $cfilename ne $row->{'rpath'} );

			return $c->render(text => "File is finishing processing (calculating hashsum), please retry in some seconds") if $row->{'processing'};
			
			my $file = $row->{'type'} eq 'link' ? $row->{'link'} : $main->build_filepath( $row->{'storage'},$row->{'urlpath'},$row->{'rpath'} );
			
			return $c->render(text => "File not available right now (perhaps storage unmounted?)") unless -f $file;
			my $dlfilename = $cfilename || $row->{'rpath'};


			if ( $row->{'size'} < $main->{conf}->{CONTENT_VIEW_UNTIL_SIZE} and $row->{'ftype'} =~ /^(image\/|text\/|video\/|application\/pdf)/) {

				if ( $row->{'ftype'} =~ /^image\// ) {
					if ( !$cfilename ) {
						return $c->redirect_to(join('/',$row->{'urlpath'}, $dlfilename));
					} else {
						$c->res->headers->content_type( $row->{'ftype'} );
					}
				} elsif ( $row->{'ftype'} =~ /^text\// ) {
					$c->res->headers->content_type( 'text/plain; charset=utf-8');
				}elsif ( $row->{'ftype'} =~ /^application\/pdf/ ) {
					$c->res->headers->content_disposition("inline; filename=$dlfilename");
				}
				
			} elsif ( $row->{'size'} < $main->{conf}->{CONTENT_VIEW_VIDEO_AUDIO_UNTIL_SIZE} and $row->{'ftype'} =~ /^(video\/|audio\/|)/) {

					if ( !$cfilename ) {
						return $c->redirect_to(join('/',$row->{'urlpath'}, $dlfilename));
					} else {
						$c->res->headers->content_type( $row->{'ftype'} );
					}

			} else {
				
				$c->res->headers->content_disposition("attachment; filename=$dlfilename");
				
			}
			
			$c->reply->asset(Mojo::Asset::File->new(path => $file));
			
			

			if ( $row->{'autodestroy'} ) {
				$main->delete_file('mpath', $row->{'mpath'});
				say '[info] File destroyed on download' if $main->{conf}->{DEBUG} > 0;
			}
		}
	);
};

app->start;
