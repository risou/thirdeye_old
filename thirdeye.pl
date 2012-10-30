#!/usr/bin/env perl
use strict;
use warnings;

use AnyEvent::Twitter::Stream;
use AnyEvent::HTTP;
use HTTP::Request::Common;
use Config::Pit;
use Encode;

my $conf = pit_get(
	'thirdeye',
	require => {
		consumer_key	=> "consumer_key",
		consumer_secret	=> "consumer_secret",
		token			=> "token",
		token_secret	=> "token_secret",
		keywords		=> "keywords",
		targets			=> "targets",
		delimiter		=> "delimiter",
		imkayacid		=> "imkayacid",
		imkayacpass		=> "imkayacpass",
		user			=> "user",
	}
);

my $keywords = split_string($conf->{keywords}, $conf->{delimiter});
my $targets = split_string($conf->{targets}, $conf->{delimiter});

my $cv = AnyEvent->condvar;

my $st = AnyEvent::Twitter::Stream->new(
	consumer_key		=> $conf->{consumer_key},
	consumer_secret		=> $conf->{consumer_secret},
	access_token		=> $conf->{token},
	access_token_secret	=> $conf->{token_secret},
	method				=> "userstream",
	on_tweet			=> sub {
		my $tweet = shift;
		my $user = $tweet->{user}{screen_name};
		my $name = encode_utf8($tweet->{user}{name});
		return unless $user && $name;
		# followしてない人のmention,retweetをとれるか確認する
		# retweet
		if (my $retweet = $tweet->{retweeted_status}) {
			if ($retweet->{user}{screen_name} eq $conf->{user}) {
				my $text = encode_utf8($tweet->{text} || '');
				# im.kayac
				my $message = "[retweet] $user/$name: $text";
				imkayac_post($conf->{imkayacid}, $message, $conf->{imkayacpass});
			}
		}
		else {
			my $text = encode_utf8($tweet->{text} || '');
			# mention
			for my $mention (@{$tweet->{entities}{user_mentions}}) {
				if ($mention->{screen_name} eq $conf->{user}) {
					# im.kayac
					my $message = "[mention] $user/$name: $text";
					imkayac_post($conf->{imkayacid}, $message, $conf->{imkayacpass});
					return;
				}
			}
			# DM
			# 監視対象		
			for my $target (@$targets) {
				if ($target eq $user) {
					# im.kayac
					my $message = "[target] $user/$name: $text";
					imkayac_post($conf->{imkayacid}, $message, $conf->{imkayacpass});
					return;
				}
			}
			# keyword check
			for my $keyword (@$keywords) {
				if ($text =~ /${keyword}/) {
					# im.kayac
					my $message = "[keyword] $user/$name: $text";
					imkayac_post($conf->{imkayacid}, $message, $conf->{imkayacpass});
					return;
				}
			}
		}
	},
	on_event			=> sub {
		# fav
		my $tweet = shift;
		my $event = $tweet->{event};
		my $user = $tweet->{user}{screen_name};
		my $name = encode_utf8($tweet->{user}{name});
		my $text = $tweet->{target_object} ? encode_utf8($tweet->{target_object}{text}) : '';
	},
	on_error			=> sub {
		my $error = shift;
		warn "ERROR: $error";
		$cv->send;
	},
	on_eof				=> sub {
		$cv->send;
	},
);

$cv->recv;

sub split_string {
	my $str = shift;
	my $delimiter = shift;
	my @words = split(/${delimiter}/, $str);
	return \@words;
}

sub imkayac_post {
	my ($user, $message, $pass) = @_;
	my $req = POST "http://im.kayac.com/api/post/${user}", [
		message => decode_utf8($message),
		password => $pass,
		handler => 'tweetbot://',
	];
	my %headers = map { $_ => $req->header($_), } $req->headers->header_field_names;
	my $r;
	$r = http_post $req->uri, $req->content, headers => \%headers, sub { undef $r };
}
